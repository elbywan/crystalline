require "compiler/crystal/syntax"
require "lsp/server"
require "../position_utils"
require "../utils"
require "./resolver"

module Crystalline::Lightweight
  # Computes the selection range chains of a document: for each requested
  # position, the AST node spans enclosing it (innermost first), then the
  # cursor line and the whole document when they enclose the previous range.
  #
  # Each range of a chain is contained in its parent, as the protocol
  # requires: the spans are ordered by increasing size and an outer span
  # that does not enclose the previously kept one (a `Call` whose
  # `end_location` stops before its block, for instance) is dropped.
  class SelectionRange
    def self.ranges(source : String, positions : Array(LSP::Position), lines : Array(String)) : Array(LSP::SelectionRange)
      new(source, lines).ranges(positions)
    end

    def initialize(@source : String, @lines : Array(String))
    end

    def ranges(positions : Array(LSP::Position)) : Array(LSP::SelectionRange)
      # A syntax error must never escape: a broken buffer still answers,
      # from the token under the cursor and from the line and document
      # ranges.
      ast = begin
        Crystal::Parser.new(@source).parse
      rescue Crystal::SyntaxException
        nil
      end

      positions.map { |position| chain_for(position, ast) }
    end

    private def chain_for(position : LSP::Position, ast : Crystal::ASTNode?) : LSP::SelectionRange
      ranges = [] of LSP::Range
      line = @lines[position.line]?

      if line && ast
        # Crystal columns count characters while the requested column counts
        # UTF-16 code units: convert before comparing, and shift to the
        # 1-based columns of `Crystal::Location`.
        cursor = {position.line + 1, PositionUtils.utf16_to_char_index(line, position.character) + 1}
        enclosing_spans(ast, cursor).each do |span|
          ranges << node_range(span)
        end
      end

      # No node encloses the position (a broken buffer or a comment): fall
      # back to the token under the cursor, when there is one.
      if ranges.empty? && line
        if span = Resolver.token_span(line, position.character)
          ranges << token_range(position.line, span)
        end
      end

      append_range(ranges, line_range(position.line))
      append_range(ranges, document_range)
      build_chain(ranges)
    end

    # The spans of every node enclosing *cursor* (a 1-based Crystal
    # line/column pair), innermost first.
    #
    # Spans are sorted by size and an outer span that does not enclose the
    # previously kept one is dropped, which guarantees that every range of
    # the resulting chain is contained in its parent.
    private def enclosing_spans(ast : Crystal::ASTNode, cursor : {Int32, Int32})
      visitor = SpanVisitor.new(cursor)
      ast.accept(visitor)

      kept = [] of {Crystal::Location, Crystal::Location}
      visitor.spans.sort_by { |(start_location, end_location)| span_size(start_location, end_location) }.each do |span|
        kept << span if kept.empty? || encloses?(span, kept.last)
      end
      kept
    end

    private def span_size(start_location : Crystal::Location, end_location : Crystal::Location) : {Int32, Int32}
      {end_location.line_number - start_location.line_number, end_location.column_number - start_location.column_number}
    end

    # Whether the *inner* span is contained in the *outer* one.
    private def encloses?(outer : {Crystal::Location, Crystal::Location}, inner : {Crystal::Location, Crystal::Location}) : Bool
      outer_start, outer_end = outer
      inner_start, inner_end = inner

      {outer_start.line_number, outer_start.column_number} <= {inner_start.line_number, inner_start.column_number} &&
        {inner_end.line_number, inner_end.column_number} <= {outer_end.line_number, outer_end.column_number}
    end

    # A node span as an LSP range. Crystal end locations point at the last
    # character of the node while LSP ranges exclude their end: shift the
    # end by one character so the range covers the whole node.
    private def node_range(span : {Crystal::Location, Crystal::Location}) : LSP::Range
      start_location, end_location = span
      Utils.lsp_range(@lines, start_location, exclusive_end(end_location))
    end

    private def exclusive_end(location : Crystal::Location) : Crystal::Location
      Crystal::Location.new(location.filename, location.line_number, location.column_number + 1)
    end

    # The range covering the token `span` (character indices) of the cursor
    # line, which `Resolver.token_span` leaves nil for whitespace and
    # punctuation.
    private def token_range(line_index : Int32, span : {Int32, Int32}) : LSP::Range
      start_index, end_index = span
      location = Crystal::Location.new(nil, line_index + 1, start_index + 1)
      Utils.lsp_range(@lines, location, end_index - start_index)
    end

    # The cursor line, its line terminator excluded.
    private def line_range(line_index : Int32) : LSP::Range?
      line = @lines[line_index]?
      return unless line

      LSP::Range.new(
        start: LSP::Position.new(line: line_index, character: 0),
        end: LSP::Position.new(line: line_index, character: content_length(line)),
      )
    end

    # The whole document, ending on the last line content.
    private def document_range : LSP::Range
      if last_line = @lines.last?
        LSP::Range.new(
          start: LSP::Position.new(line: 0, character: 0),
          end: LSP::Position.new(line: @lines.size - 1, character: content_length(last_line)),
        )
      else
        # An empty document still answers with a range: a chain is never
        # empty.
        LSP::Range.new(
          start: LSP::Position.new(line: 0, character: 0),
          end: LSP::Position.new(line: 0, character: 0),
        )
      end
    end

    # The line content length in UTF-16 code units.
    private def content_length(line : String) : Int32
      content = line.chomp
      PositionUtils.char_to_utf16_index(content, content.size)
    end

    private def append_range(ranges : Array(LSP::Range), range : LSP::Range?)
      return unless range
      return unless ranges.empty? || covers?(range, ranges.last)

      ranges << range
    end

    # Whether *outer* covers *inner*, the invariant a selection range chain
    # must satisfy.
    private def covers?(outer : LSP::Range, inner : LSP::Range) : Bool
      {outer.start.line, outer.start.character} <= {inner.start.line, inner.start.character} &&
        {inner.end.line, inner.end.character} <= {outer.end.line, outer.end.character}
    end

    # Links the ranges (innermost first) through their parents, from the
    # outside in: the returned head is the innermost range, whose parent is
    # the next one, up to the outermost range.
    private def build_chain(ranges : Array(LSP::Range)) : LSP::SelectionRange
      head = LSP::SelectionRange.new(range: ranges.last)
      ranges[0...-1].reverse_each do |range|
        head = LSP::SelectionRange.new(range: range, parent: head)
      end
      head
    end
  end

  # Collects the spans of every node enclosing a cursor.
  private class SpanVisitor < Crystal::Visitor
    getter spans = [] of {Crystal::Location, Crystal::Location}

    def initialize(@cursor : {Int32, Int32})
    end

    def visit(node : Crystal::ASTNode) : Bool
      if (start_location = node.location) && (end_location = node.end_location)
        if {start_location.line_number, start_location.column_number} <= @cursor &&
           @cursor <= {end_location.line_number, end_location.column_number}
          @spans << {start_location, end_location}
        end
      end
      true
    end
  end
end
