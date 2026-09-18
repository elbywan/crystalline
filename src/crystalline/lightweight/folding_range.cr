require "compiler/crystal/syntax"
require "lsp/server"

module Crystalline::Lightweight
  # Computes the foldable regions of a document.
  #
  # The ranges are line based: a client folding one hides the lines following
  # `start_line` up to and including `end_line`, so `end_line` is the line of
  # the closing `end` (or closing quote of a multiline literal) and the
  # character fields are left empty.
  class FoldingRange
    def self.ranges(source : String) : Array(LSP::FoldingRange)?
      new(source).ranges
    end

    def initialize(@source : String)
    end

    # Nil when nothing folds (e.g. an empty or fully flat document).
    def ranges : Array(LSP::FoldingRange)?
      ranges = [] of LSP::FoldingRange
      ast_ranges = [] of LSP::FoldingRange
      literal_lines = Set(Int32).new
      if ast = parse_ast
        FoldingRangeVisitor.new(ast_ranges, literal_lines).accept(ast)
      end
      collect_line_ranges(ranges, literal_lines)
      ranges.concat(ast_ranges)
      ranges.empty? ? nil : ranges
    end

    # Comment and import streaks: consecutive lines sharing the same leading
    # marker fold into a single range. Lines inside a multi-line literal are
    # skipped: heredoc bodies may well hold `#` or `require` lines.
    private def collect_line_ranges(ranges : Array(LSP::FoldingRange), literal_lines : Set(Int32))
      lines = @source.lines(chomp: false)
      index = 0
      while index < lines.size
        kind = literal_lines.includes?(index) ? nil : line_kind(lines[index])
        if kind.nil?
          index += 1
          next
        end

        start = index
        index += 1
        while index < lines.size && !literal_lines.includes?(index) && line_kind(lines[index]) == kind
          index += 1
        end

        ranges << LSP::FoldingRange.new(start_line: start, end_line: index - 1, kind: kind) if index - start > 1
      end
    end

    private def line_kind(line : String) : LSP::FoldingRangeKind?
      stripped = line.lstrip
      return LSP::FoldingRangeKind::Comment if stripped.starts_with?('#')
      return LSP::FoldingRangeKind::Imports if stripped.starts_with?("require ")
      nil
    end

    # A syntax error degrades gracefully: the node ranges are dropped while
    # the line ranges (comments, requires) still fold.
    private def parse_ast : Crystal::ASTNode?
      Crystal::Parser.new(@source).parse
    rescue Crystal::SyntaxException
      nil
    end
  end

  # Collects one range per node that owns a closing `end` (or a multiline
  # literal span), walking the tree in source order.
  private class FoldingRangeVisitor < Crystal::Visitor
    def initialize(@ranges : Array(LSP::FoldingRange), @literal_lines : Set(Int32))
      @spans = Set({Int32, Int32}).new
    end

    # A multi-line literal folds, and the lines it spans are recorded: their
    # content is not code, comments or imports.
    def visit(node : Crystal::StringLiteral | Crystal::StringInterpolation | Crystal::RegexLiteral)
      if (location = node.location) && (end_location = node.end_location)
        ((location.line_number)..(end_location.line_number - 1)).each { |line| @literal_lines << line }
      end
      add_node_range(node)
      true
    end

    def visit(node : Crystal::ASTNode)
      add_node_range(node)
      true
    end

    private def add_node_range(node : Crystal::ASTNode) : Nil
      return unless start_location = node.location
      return unless end_location = node.end_location
      return unless foldable?(node)

      start_line = start_location.line_number - 1
      end_line = end_location.line_number - 1
      # A postfix condition shares its span with the block it guards
      # (`return unless x.all? do ... end`): keep one range per span.
      return unless end_line > start_line
      return unless @spans.add?({start_line, end_line})

      @ranges << LSP::FoldingRange.new(start_line: start_line, end_line: end_line)
    end

    private def foldable?(node : Crystal::ASTNode) : Bool
      case node
      when Crystal::Expressions
        # A `begin ... end` block without handler parses as a keyworded
        # expressions node spanning the `begin`/`end` pair.
        node.keyword.begin?
      when Crystal::StringLiteral, Crystal::ClassDef, Crystal::ModuleDef, Crystal::EnumDef, Crystal::LibDef,
           Crystal::AnnotationDef, Crystal::Def, Crystal::Macro, Crystal::If, Crystal::Unless, Crystal::While,
           Crystal::Until, Crystal::Case, Crystal::Select, Crystal::Block, Crystal::ExceptionHandler
        true
      else
        false
      end
    end
  end
end
