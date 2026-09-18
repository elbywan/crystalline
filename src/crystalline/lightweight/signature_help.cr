require "lsp/server"
require "compiler/crystal/syntax"
require "../position_utils"
require "./query"
require "./resolver"

module Crystalline::Lightweight
  # Signature help: finds the call whose arguments the cursor sits in and
  # renders the signatures of its resolved candidates, highlighting the
  # parameter between the last top-level comma and the cursor.
  #
  # The source is masked with the compiler lexer (a per-file `SourceMask`
  # does not know regexes, backticks, `%w()`/`%q()`/`%r()` literals or
  # heredocs): parentheses, commas and brackets inside comments and
  # literals must not take part in the scans. Mid-edit buffers commonly
  # fail to lex (an unterminated literal): the spans collected before the
  # failure are kept and the scan degrades.
  class SignatureHelp
    # A masked character span `[start, end)` (character offsets into the source).
    record Span, start : Int32, end : Int32

    # The callable before the paren, its receiver chain (empty for a bare
    # call) and the analysis position: the trailing dot for a receiver
    # call, the opening paren otherwise.
    record Target, name : String, receiver : String, line_index : Int32, char_column : Int32

    @masked : Array(Span)

    def self.help(source : String, line_number : Int32, column_number : Int32, query : Query?) : LSP::SignatureHelp?
      new(source, line_number, column_number, query).run
    end

    def initialize(@source : String, @line_number : Int32, @column_number : Int32, @query : Query?)
      @lines = @source.lines(chomp: false)
      @chars = @source.chars
      @line_starts = [] of Int32
      offset = 0
      @lines.each do |line|
        @line_starts << offset
        offset += line.size
      end
      @spans = [] of Span
      @heredocs = [] of Crystal::Token::DelimiterState
      @char_offset = 0
      @lexer = Crystal::Lexer.new(@source)
      @lexer.comments_enabled = true
      @masked = merged_spans(collect_spans)
    end

    def run : LSP::SignatureHelp?
      query = @query
      return unless query

      line = @lines[@line_number]?
      return unless line

      cursor = @line_starts[@line_number] + PositionUtils.utf16_to_char_index(line, @column_number)
      return if masked?(cursor)

      open_offset = unclosed_paren_offset(cursor)
      return unless open_offset

      target = call_target(open_offset)
      return unless target

      methods = resolve_candidates(target, query)
      return if methods.empty?

      signatures = methods.map { |method| signature_information(method) }
      counts = signatures.map { |signature| signature.parameters.try(&.size) || 0 }
      active_signature, active_parameter = active_entry(counts, top_level_commas(open_offset, cursor))

      LSP::SignatureHelp.new(
        signatures: signatures,
        active_signature: active_signature,
        active_parameter: active_parameter,
      )
    end

    # The first candidate that can hold *commas* parameters is the active
    # one; when none can (more commas than any overload declares), the
    # largest one is kept with its last parameter active, so the reported
    # parameter always indexes `signatures[active_signature].parameters`.
    private def active_entry(counts : Array(Int32), commas : Int32) : {Int32, Int32?}
      if index = counts.index { |count| count > commas }
        {index, counts[index].zero? ? nil : commas}
      else
        largest = counts.max
        {counts.index(largest).not_nil!, largest.zero? ? nil : largest - 1}
      end
    end

    # The innermost unclosed `(` before the cursor. Brackets are counted
    # with a reverse stack so a closer matches its own opener type: a `)`
    # nested in a call argument or a `(` right after a `[` does not end the
    # scan early. Unmatched openers of the other kinds (`[`, `{`) are
    # crossed: the forward comma scan accounts for their depth.
    private def unclosed_paren_offset(cursor : Int32) : Int32?
      stack = [] of Char
      index = cursor - 1
      span_index = @masked.size - 1
      while index >= 0
        while span_index >= 0 && @masked[span_index].start > index
          span_index -= 1
        end
        if span_index >= 0 && index < @masked[span_index].end
          index = @masked[span_index].start - 1
          next
        end

        case @chars[index]
        when ')'
          stack << '('
        when ']'
          stack << '['
        when '}'
          stack << '{'
        when '(', '[', '{'
          if stack.empty?
            return index if @chars[index] == '('
          else
            stack.pop
          end
        end
        index -= 1
      end
      nil
    end

    # Comma count at depth zero between the open paren and the cursor.
    private def top_level_commas(open_offset : Int32, cursor : Int32) : Int32
      depth = 0
      count = 0
      span_index = @masked.bsearch_index { |span| span.end > open_offset } || @masked.size
      index = open_offset + 1
      while index < cursor
        while span_index < @masked.size && @masked[span_index].end <= index
          span_index += 1
        end
        if span_index < @masked.size && @masked[span_index].start <= index
          index = @masked[span_index].end
          next
        end

        case @chars[index]
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1
        when ','
          count += 1 if depth.zero?
        end
        index += 1
      end
      count
    end

    # The called name before the paren, skipping the spaces `foo (1)`
    # leaves between the name and its argument list.
    private def call_target(open_offset : Int32) : Target?
      index = open_offset - 1
      while index >= 0 && @chars[index].in?(' ', '\t')
        index -= 1
      end
      name_end = index + 1
      name_start = name_end
      while name_start > 0 && method_name_char?(@chars[name_start - 1])
        name_start -= 1
      end
      return if name_start == name_end

      name = String.build { |str| (name_start...name_end).each { |i| str << @chars[i] } }
      unless name_start > 0 && @chars[name_start - 1] == '.'
        opener_line = line_index_for(open_offset)
        return Target.new(name, "", opener_line, open_offset - @line_starts[opener_line])
      end

      dot = name_start - 1
      line_index = line_index_for(dot)
      char_column = dot - @line_starts[line_index]
      receiver = Resolver.receiver_from_line_prefix(@source, line_index, @lines[line_index][0, char_column])
      # An empty chain (`{1 => 2}.foo`) must not fall back to a bare-call
      # resolution: that would highlight the enclosing type's same-named
      # method instead of the receiver's.
      return if receiver.empty?

      Target.new(name, receiver, line_index, char_column)
    end

    private def resolve_candidates(target : Target, query : Query) : Array(MethodInfo)
      if target.receiver.empty?
        # A bare call may be a self-call (`bar(1)` inside the type defining
        # `bar`): the enclosing type's methods win, the top-level ones are
        # the fallback.
        type_names, class_method = Resolver.receiver_types(
          @source, target.line_index, target.char_column, "self", query,
        )
        methods = type_names.flat_map { |type_name| query.methods_named(type_name, target.name, class_method: class_method) }
        return methods unless methods.empty?

        query.top_level_methods.select(&.name.==(target.name))
      else
        type_names, class_method = Resolver.receiver_types(
          @source, target.line_index, target.char_column, target.receiver, query,
        )
        type_names.flat_map { |type_name| query.methods_named(type_name, target.name, class_method: class_method) }
      end
    end

    private def signature_information(method : MethodInfo) : LSP::SignatureInformation
      parameters = [] of LSP::ParameterInformation
      label = signature_label(method, parameters)
      LSP::SignatureInformation.new(label: label, documentation: nil, parameters: parameters)
    end

    # `name(a : Int32, *args, **options, &block) : Return`, recording each
    # parameter's byte span in the label so clients can highlight the
    # active one. Splat, double-splat and block arguments are never
    # dropped: a wrong signature is worse than none.
    private def signature_label(method : MethodInfo, parameters : Array(LSP::ParameterInformation)) : String
      String.build do |str|
        str << method.name
        str << '('
        printed = false
        method.args.each do |arg|
          str << ", " if printed
          printed = true
          str << '*' if arg.splat
          parameters << parameter_information(str, arg)
        end
        if double_splat = method.double_splat
          str << ", " if printed
          printed = true
          str << "**"
          parameters << parameter_information(str, double_splat)
        end
        if block_arg = method.block_arg
          str << ", " if printed
          str << '&'
          parameters << parameter_information(str, block_arg)
        end
        str << ')'
        str << " : " << method.return_type if method.return_type
      end
    end

    private def parameter_information(str : String::Builder, arg : ArgInfo) : LSP::ParameterInformation
      start = str.bytesize
      str << arg.name
      str << " : " << arg.restriction if arg.restriction
      LSP::ParameterInformation.new(label: {start, str.bytesize}, documentation: nil)
    end

    private def masked?(offset : Int32) : Bool
      index = @masked.bsearch_index { |span| span.end > offset }
      index ? offset >= @masked[index].start : false
    end

    private def line_index_for(offset : Int32) : Int32
      index = @line_starts.bsearch_index { |start| start > offset }
      index ? index - 1 : @line_starts.size - 1
    end

    # Nesting makes raw spans overlap (a string inside an interpolation is
    # recorded before the string containing it): merging keeps them sorted
    # and disjoint for the binary searches.
    private def merged_spans(spans : Array(Span)) : Array(Span)
      merged = [] of Span
      spans.sort_by(&.start).each do |span|
        if (last = merged.last?) && span.start <= last.end
          merged[merged.size - 1] = Span.new(last.start, Math.max(last.end, span.end))
        else
          merged << span
        end
      end
      merged
    end

    # Characters inside comments, symbols, char literals and every kind of
    # delimited literal (strings, regexes, commands, percent literals and
    # heredocs), as `[start, end)` character spans. `Crystal::Lexer` only
    # returns the opening delimiter: the literal body is lexed with
    # `next_string_token` the way the parser drives it, interpolations
    # switching back to code.
    private def collect_spans : Array(Span)
      loop do
        token = next_token
        break unless token
        case token.type
        when .eof?
          break
        when .comment?, .symbol?, .char?
          @spans << Span.new(token_start(token), @char_offset)
        when .delimiter_start?, .string_array_start?, .symbol_array_start?
          start = token_start(token)
          if token.delimiter_state.kind.heredoc?
            @heredocs << token.delimiter_state
            @spans << Span.new(start, @char_offset)
          else
            consume_literal_body(token.delimiter_state)
            @spans << Span.new(start, @char_offset)
          end
        when .newline?
          consume_heredocs
        end
      end
      @spans
    end

    # Heredoc bodies start on the line following their `<<-NAME`: they are
    # consumed once that newline has been read.
    private def consume_heredocs
      return if @heredocs.empty?

      states = @heredocs.dup
      @heredocs.clear
      states.each do |state|
        start = @char_offset
        consume_literal_body(state)
        @spans << Span.new(start, @char_offset)
      end
    end

    private def consume_literal_body(state : Crystal::Token::DelimiterState)
      loop do
        token = next_string_token(state)
        break unless token
        case token.type
        when .eof?, .delimiter_end?, .string_array_end?
          break
        when .interpolation_start?
          consume_interpolation
        else
          state = token.delimiter_state
        end
      end
    end

    private def consume_interpolation
      depth = 1
      loop do
        token = next_token
        break unless token
        case token.type
        when .eof?
          break
        when .op_lcurly?
          depth += 1
        when .op_rcurly?
          depth -= 1
          break if depth == 0
        when .delimiter_start?, .string_array_start?, .symbol_array_start?
          consume_literal_body(token.delimiter_state) unless token.delimiter_state.kind.heredoc?
        end
      end
    end

    private def next_token : Crystal::Token?
      from = @lexer.current_pos
      token = @lexer.next_token
      advance(from)
      token
    rescue Crystal::SyntaxException
      nil
    end

    private def next_string_token(state : Crystal::Token::DelimiterState) : Crystal::Token?
      from = @lexer.current_pos
      token = @lexer.next_string_token(state)
      advance(from)
      token
    rescue Crystal::SyntaxException
      nil
    end

    private def advance(from : Int32)
      to = @lexer.current_pos
      @char_offset += @source.byte_slice(from, to - from).size if to > from
    end

    private def token_start(token : Crystal::Token) : Int32
      if line_start = @line_starts[token.line_number - 1]?
        line_start + token.column_number - 1
      else
        @char_offset
      end
    end

    private def method_name_char?(char : Char) : Bool
      char.ascii_alphanumeric? || char.in?('_', '?', '!')
    end
  end
end
