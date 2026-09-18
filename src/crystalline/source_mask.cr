module Crystalline
  # Records which parts of a source file are comments, string literals or
  # heredoc bodies, so interactive features do not try to resolve prose as
  # code (hovering the word "requests" inside a comment must be a graceful
  # miss, not a resolution attempt).
  class SourceMask
    @ranges = {} of Int32 => Array(Range(Int32, Int32))
    @comment_starts = {} of Int32 => Int32
    @heredoc_terminators = [] of String

    def initialize(source : String)
      scan(source)
    end

    def comment_or_string?(line : Int32, column : Int32) : Bool
      @ranges[line]?.try(&.any? { |range| range.covers?(column) }) || false
    end

    # The character index where a comment starts on *line*, or nil. Only a `#`
    # outside a literal starts a comment: the mask knows which ones do.
    def comment_start(line : Int32) : Int32?
      @comment_starts[line]?
    end

    private def scan(source : String)
      source.lines(chomp: false).each_with_index do |line, line_index|
        # Heredoc bodies span lines: mask everything until the terminator.
        if terminator = @heredoc_terminators.first?
          if line.strip == terminator
            @heredoc_terminators.delete_at(0)
          else
            (@ranges[line_index] ||= [] of Range(Int32, Int32)) << (0...line.size)
            next
          end
        end

        mask_line(line, line_index)
        detect_heredoc(line)
      end
    end

    # Masks comments, double-quoted strings and char literals on one line.
    private def mask_line(line : String, line_index : Int32)
      ranges = [] of Range(Int32, Int32)
      index = 0
      while index < line.size
        case line[index]
        when '#'
          @comment_starts[line_index] = index
          ranges << (index...line.size)
          break
        when '"'
          index += 1
          string_start = index - 1
          interpolation_start = -1
          interpolation_depth = 0
          while index < line.size
            if line[index] == '\\'
              index += 2
              next
            end
            if interpolation_depth > 0
              if line[index] == '{'
                interpolation_depth += 1
              elsif line[index] == '}'
                interpolation_depth -= 1
                if interpolation_depth == 0
                  # The interpolation body is code, not string content:
                  # leave it unmasked.
                  ranges << (string_start...interpolation_start) if string_start < interpolation_start
                  string_start = index + 1
                end
              end
              index += 1
              next
            end
            if line[index] == '#' && line[index + 1]? == '{'
              interpolation_start = index
              interpolation_depth = 1
              index += 2
              next
            end
            break if line[index] == '"'
            index += 1
          end
          index += 1 if index < line.size
          ranges << (string_start...index) if string_start < index
        when '\''
          start = index
          index += 1
          while index < line.size
            if line[index] == '\\'
              index += 2
              next
            end
            break if line[index] == '\''
            index += 1
          end
          index += 1 if index < line.size
          ranges << (start...index)
        else
          index += 1
        end
      end
      @ranges[line_index] = ranges unless ranges.empty?
    end

    # Detects `<<-IDENT` / `<<~IDENT` heredoc openers (the unambiguous forms;
    # a bare `<<IDENT` is indistinguishable from a shift-left expression).
    private def detect_heredoc(line : String)
      if match = line.match(/\<\<[-~]([A-Za-z_]\w*)\s*$/)
        @heredoc_terminators << match[1]
      end
    end
  end
end
