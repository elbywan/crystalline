require "lsp/server"
require "compiler/crystal/syntax"
require "../source_mask"
require "../position_utils"

module Crystalline::Lightweight
  # Computes the semantic tokens of a document: the token types and modifiers
  # are announced in the legend, the data is the flat array of relative
  # 5-tuples the protocol defines.
  #
  # Tokens come from the syntax tree, with the source text checked before a
  # token is emitted: macro generated nodes carry locations of the macro call
  # site (or none), and a wrong token is worse than a missing one. Literals
  # spanning several lines (heredocs) only color their first line, the
  # remaining lines are left to the client's own grammar.
  #
  # Clients keep their grammar based highlighting for everything that is not
  # tokenized here (keywords inside expressions, operators, interpolations).
  class SemanticTokens
    TOKEN_TYPES = [
      "namespace",
      "type",
      "class",
      "struct",
      "enum",
      "interface",
      "parameter",
      "variable",
      "property",
      "function",
      "method",
      "macro",
      "keyword",
      "comment",
      "string",
      "number",
      "regexp",
      "enumMember",
    ]

    NAMESPACE   =  0
    TYPE        =  1
    CLASS       =  2
    STRUCT      =  3
    ENUM        =  4
    INTERFACE   =  5
    PARAMETER   =  6
    VARIABLE    =  7
    PROPERTY    =  8
    FUNCTION    =  9
    METHOD      = 10
    MACRO       = 11
    KEYWORD     = 12
    COMMENT     = 13
    STRING      = 14
    NUMBER      = 15
    REGEXP      = 16
    ENUM_MEMBER = 17

    record Token, line : Int32, character : Int32, length : Int32, type : Int32

    def self.legend : LSP::SemanticTokensLegend
      LSP::SemanticTokensLegend.new(token_types: TOKEN_TYPES, token_modifiers: [] of String)
    end

    def self.tokens(source : String) : LSP::SemanticTokens?
      new(source).tokens
    end

    def initialize(@source : String)
      @lines = source.lines(chomp: false)
      @tokens = [] of Token
    end

    def tokens : LSP::SemanticTokens?
      begin
        Crystal::Parser.new(@source).parse.accept(Visitor.new(self))
      rescue Crystal::SyntaxException
        # Mid-edit buffers often do not parse: the comments are still known
        # exactly (the mask is line based), the rest is left to the client.
      end
      collect_comments

      return if @tokens.empty?

      data = encode(sorted_tokens)
      LSP::SemanticTokens.new(data: data, result_id: nil)
    end

    private def encode(tokens : Array(Token)) : Array(Int32)
      data = [] of Int32
      previous_line = 0
      previous_character = 0
      tokens.each do |token|
        delta_line = token.line - previous_line
        delta_character = delta_line == 0 ? token.character - previous_character : token.character
        data << delta_line << delta_character << token.length << token.type << 0
        previous_line = token.line
        previous_character = token.character
      end
      data
    end

    # Sorted by position, with tokens overlapping the previous one dropped:
    # clients that do not announce `overlappingTokenSupport` require it.
    private def sorted_tokens : Array(Token)
      sorted = @tokens.sort_by { |token| {token.line, token.character} }
      unique = [] of Token
      sorted.each do |token|
        if (last = unique.last?) && last.line == token.line && last.character + last.length > token.character
          next
        end
        unique << token
      end
      unique
    end

    private def collect_comments : Nil
      mask = SourceMask.new(@source)
      @lines.each_with_index do |line, line_index|
        next unless index = mask.comment_start(line_index)

        add_token(line_index, index, line.rstrip.size - index, COMMENT)
      end
    end

    # Adds a token for the *text* expected at *location*, unless the source
    # does not hold it (macro generated nodes reuse the macro call site).
    # Internal: adds a token for the *text* expected at *location*.
    def add_text(location : Crystal::Location?, text : String, type : Int32) : Nil
      return unless location
      return if text.empty?

      add_token(location.line_number - 1, location.column_number - 1, text.size, type, expected: text)
    end

    # Internal: the (possibly qualified) name of a declaration.
    #
    # `name_location` cannot be used for this: it is nil for `enum` and
    # `alias`, points at the last segment for `class` and at the first one for
    # `module`. The name always follows the declaration keyword, so it is
    # located from there and every segment is checked against the source.
    def add_declaration_name(keyword_location : Crystal::Location?, keyword : String, path : Crystal::Path, type : Int32) : Nil
      return unless keyword_location

      line = @lines[keyword_location.line_number - 1]?
      return unless line

      offset = keyword_location.column_number - 1 + keyword.size
      while offset < line.size && line[offset].whitespace?
        offset += 1
      end
      emit_path_segments(keyword_location.line_number - 1, offset, path, type)
    end

    # Internal: the segments of a path expression: every segment but the last
    # names a namespace.
    def add_path(path : Crystal::Path, type : Int32 = TYPE) : Nil
      return unless location = path.location

      emit_path_segments(location.line_number - 1, location.column_number - 1, path, type)
    end

    private def emit_path_segments(line_index : Int32, offset : Int32, path : Crystal::Path, type : Int32) : Nil
      path.names.each_with_index do |name, index|
        add_token(line_index, offset, name.size, index == path.names.size - 1 ? type : NAMESPACE, expected: name)
        offset += name.size + 2
      end
    end

    # Internal: adds a token covering a node span (literals).
    def add_span(location : Crystal::Location?, end_location : Crystal::Location?, type : Int32) : Nil
      return unless location && end_location

      start_line = location.line_number - 1
      end_line = end_location.line_number - 1
      start_column = location.column_number - 1

      if start_line == end_line
        add_token(start_line, start_column, end_location.column_number - location.column_number + 1, type)
        return
      end

      # A multi-line literal (heredoc, multi-line string) is tokenized line by
      # line, so that nothing else (a `#` inside it, for instance) is reported
      # within its body.
      line = @lines[start_line]?
      return unless line

      add_token(start_line, start_column, line.size - start_column, type)
      ((start_line + 1)..end_line).each do |line_index|
        line = @lines[line_index]?
        next unless line

        length = line_index == end_line ? end_location.column_number : line.size
        add_token(line_index, 0, length, type)
      end
    end

    # Internal: adds a token covering *length* characters from *start* (both
    # character based, converted to the UTF-16 columns the protocol uses).
    def add_token(line_index : Int32, start : Int32, length : Int32, type : Int32, expected : String? = nil) : Nil
      line = @lines[line_index]?
      return unless line
      return if start < 0 || length <= 0 || start >= line.size

      length = Math.min(length, line.rstrip.size - start)
      return if length <= 0
      return if expected && line[start, expected.size]? != expected

      utf16_start = PositionUtils.char_to_utf16_index(line, start)
      utf16_end = PositionUtils.char_to_utf16_index(line, start + length)
      @tokens << Token.new(line: line_index, character: utf16_start, length: utf16_end - utf16_start, type: type)
    end

    private class Visitor < Crystal::Visitor
      def initialize(@tokens : SemanticTokens)
        @type_depth = 0
      end

      def visit(node : Crystal::ClassDef)
        add_keyword(node, node.struct? ? "struct" : "class")
        @tokens.add_declaration_name(node.location, node.struct? ? "struct" : "class", node.name, node.struct? ? STRUCT : CLASS)
        @type_depth += 1
        true
      end

      def end_visit(node : Crystal::ClassDef)
        add_end_keyword(node)
        @type_depth -= 1
      end

      def visit(node : Crystal::ModuleDef)
        add_keyword(node, "module")
        @tokens.add_declaration_name(node.location, "module", node.name, NAMESPACE)
        @type_depth += 1
        true
      end

      def end_visit(node : Crystal::ModuleDef)
        add_end_keyword(node)
        @type_depth -= 1
      end

      def visit(node : Crystal::EnumDef)
        add_keyword(node, "enum")
        @tokens.add_declaration_name(node.location, "enum", node.name, ENUM)
        @type_depth += 1
        # Members are `Arg`, `Path` or `Assign` nodes: handled here, because the
        # generic traversal would report them as parameters.
        node.members.each do |member|
          value = add_enum_member(member)
          value.try &.accept(self)
        end
        add_end_keyword(node)
        @type_depth -= 1
        false
      end

      def visit(node : Crystal::LibDef)
        add_keyword(node, "lib")
        @tokens.add_declaration_name(node.location, "lib", node.name, INTERFACE)
        true
      end

      def end_visit(node : Crystal::LibDef)
        add_end_keyword(node)
      end

      def visit(node : Crystal::AnnotationDef)
        add_keyword(node, "annotation")
        @tokens.add_declaration_name(node.location, "annotation", node.name, INTERFACE)
        true
      end

      def end_visit(node : Crystal::AnnotationDef)
        add_end_keyword(node)
      end

      def visit(node : Crystal::Alias)
        add_keyword(node, "alias")
        @tokens.add_declaration_name(node.location, "alias", node.name, TYPE)
        true
      end

      def visit(node : Crystal::Def)
        add_keyword(node, "def")
        @tokens.add_text(node.name_location, node.name.sub(/=$/, ""), @type_depth > 0 ? METHOD : FUNCTION)
        true
      end

      def end_visit(node : Crystal::Def)
        add_end_keyword(node)
      end

      def visit(node : Crystal::Macro)
        add_keyword(node, "macro")
        @tokens.add_text(node.name_location, node.name, MACRO)
        true
      end

      def end_visit(node : Crystal::Macro)
        add_end_keyword(node)
      end

      def visit(node : Crystal::Arg)
        @tokens.add_text(node.location, node.name, PARAMETER)
        true
      end

      # Block arguments are `Var` nodes and handled as variables.
      def visit(node : Crystal::Var)
        @tokens.add_text(node.location, node.name, VARIABLE)
        true
      end

      def visit(node : Crystal::InstanceVar)
        @tokens.add_text(node.location, node.name, PROPERTY)
        true
      end

      def visit(node : Crystal::ClassVar)
        @tokens.add_text(node.location, node.name, PROPERTY)
        true
      end

      def visit(node : Crystal::Call)
        if name_location = node.name_location
          size = node.name_size
          @tokens.add_text(name_location, node.name[0, size], METHOD) if size > 0
        end
        true
      end

      def visit(node : Crystal::Path)
        @tokens.add_path(node)
        true
      end

      def visit(node : Crystal::StringLiteral)
        @tokens.add_span(node.location, node.end_location, STRING)
        true
      end

      def visit(node : Crystal::StringInterpolation)
        @tokens.add_span(node.location, node.end_location, STRING)
        true
      end

      def visit(node : Crystal::RegexLiteral)
        @tokens.add_span(node.location, node.end_location, REGEXP)
        true
      end

      def visit(node : Crystal::NumberLiteral)
        @tokens.add_span(node.location, node.end_location, NUMBER)
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def add_keyword(node : Crystal::ASTNode, keyword : String) : Nil
        @tokens.add_text(node.location, keyword, KEYWORD)
      end

      # The parser records the end location on the last character of the
      # closing keyword.
      # Returns the member's value, which is tokenized like any other
      # expression (`Arg` members carry it in their default value).
      private def add_enum_member(member : Crystal::ASTNode) : Crystal::ASTNode?
        case member
        when Crystal::Path
          @tokens.add_path(member, ENUM_MEMBER)
          nil
        when Crystal::Arg
          @tokens.add_text(member.location, member.name, ENUM_MEMBER)
          member.default_value
        when Crystal::Assign
          case target = member.target
          when Crystal::Path then @tokens.add_path(target, ENUM_MEMBER)
          when Crystal::Arg  then @tokens.add_text(target.location, target.name, ENUM_MEMBER)
          end
          member.value
        else
          member
        end
      end

      private def add_end_keyword(node : Crystal::ASTNode) : Nil
        return unless location = node.end_location

        start = Crystal::Location.new(location.filename, location.line_number, location.column_number - 2)
        @tokens.add_text(start, "end", KEYWORD)
      end
    end
  end
end
