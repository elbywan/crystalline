require "compiler/crystal/syntax"

class Crystalline::CompletionContext
  record TokenSpan, type : Crystal::Token::Kind, start_char : Int32, end_char : Int32

  getter trigger_character : String?
  getter analysis_column : Int32
  getter replace_start : Int32
  getter replace_end : Int32

  def self.detect(line : String, cursor : Int32, trigger_character : String?) : self?
    new(line, cursor, trigger_character).detect
  end

  def initialize(@line : String, @cursor : Int32, @trigger_character : String?)
    @analysis_column = cursor
    @replace_start = cursor
    @replace_end = cursor
  end

  def detect : self?
    fragment_start, fragment_end = identifier_fragment_bounds
    @replace_start = fragment_start
    @replace_end = fragment_end

    tokens = tokens_for_line
    return if inside_comment?(tokens)

    if @trigger_character.nil?
      @trigger_character = inferred_trigger(tokens, fragment_start)
    end

    case @trigger_character
    when "."
      if operator = preceding_period(tokens, fragment_start)
        @analysis_column = operator.start_char
        @replace_start = operator.end_char
      end
    when ":"
      if operator = preceding_colon_colon(tokens, fragment_start)
        @analysis_column = operator.start_char
        @replace_start = operator.end_char
      end
    when "@"
      if sigil = current_sigiled_token(tokens)
        @analysis_column = sigil.start_char
        @replace_start = sigil.start_char + sigil_prefix_size(sigil.type)
      elsif @cursor > 1 && @line[@cursor - 2, 2]? == "@@"
        @analysis_column = @cursor - 2
        @replace_start = @cursor
      elsif @cursor > 0 && @line[@cursor - 1] == '@'
        @analysis_column = @cursor - 1
        @replace_start = @cursor
      end
    else
      @analysis_column = @cursor
    end

    self
  rescue Crystal::SyntaxException
    nil
  end

  def analysis_prefix : String
    @line[0...@analysis_column]
  end

  def completion_range(line_number : Int32) : LSP::Range
    LSP::Range.new(
      start: LSP::Position.new(line: line_number, character: @replace_start),
      end: LSP::Position.new(line: line_number, character: @replace_end),
    )
  end

  def rewritten_line : String
    suffix = @line[@replace_end..]?
    right_offset = 0
    truncate_line = false

    suffix.try &.each_char_with_index do |char, index|
      unless ident_char?(char) || char == ':'
        truncate_line = true if char == '(' || char == '{' || char == '['
        right_offset = index
        break
      end
    end

    suffix = suffix.try &.[right_offset...]?
    analysis_prefix + (!truncate_line ? (suffix || "\n") : "\n")
  end

  private def identifier_fragment_bounds
    start_char = @cursor
    while start_char > 0 && ident_char?(@line[start_char - 1])
      start_char -= 1
    end

    end_char = @cursor
    while (char = @line[end_char]?) && ident_char?(char)
      end_char += 1
    end

    {start_char, end_char}
  end

  private def tokens_for_line
    lexer = Crystal::Lexer.new(@line)
    lexer.comments_enabled = true

    spans = [] of TokenSpan

    loop do
      token = lexer.next_token
      break if token.type.eof? || token.type.newline?
      length = token_length(token)
      spans << TokenSpan.new(
        type: token.type,
        start_char: token.column_number - 1,
        end_char: token.column_number - 1 + length,
      ) if length > 0
    end

    spans
  end

  private def token_length(token)
    case token.type
    when .ident?, .const?, .instance_var?, .class_var?, .comment?, .global?, .symbol?, .number?
      token.value.to_s.size
    when .op_colon_colon?
      2
    when .op_period?
      1
    else
      token.type.to_s.size
    end
  end

  private def inside_comment?(tokens : Array(TokenSpan))
    tokens.any? { |token| token.type.comment? && @cursor >= token.start_char }
  end

  private def inferred_trigger(tokens : Array(TokenSpan), fragment_start : Int32)
    if token = current_sigiled_token(tokens)
      return "@" if token.type.instance_var? || token.type.class_var?
    elsif @cursor > 0 && @line[@cursor - 1] == '@'
      return "@"
    end

    return "." if preceding_period(tokens, fragment_start)
    return ":" if preceding_colon_colon(tokens, fragment_start)
  end

  private def current_sigiled_token(tokens : Array(TokenSpan))
    tokens.find do |token|
      (token.type.instance_var? || token.type.class_var?) &&
        @cursor >= token.start_char &&
        @cursor <= token.end_char
    end
  end

  private def sigil_prefix_size(type : Crystal::Token::Kind)
    type.class_var? ? 2 : 1
  end

  private def preceding_period(tokens : Array(TokenSpan), fragment_start : Int32)
    tokens.reverse_each.find do |token|
      token.type.op_period? && token.end_char == fragment_start
    end
  end

  private def preceding_colon_colon(tokens : Array(TokenSpan), fragment_start : Int32)
    tokens.reverse_each.find do |token|
      token.type.op_colon_colon? && token.end_char == fragment_start
    end
  end

  private def ident_char?(char : Char)
    char.ascii_alphanumeric? || char == '_' || char == '?' || char == '!'
  end
end
