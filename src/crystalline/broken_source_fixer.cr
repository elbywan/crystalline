class Crystalline::BrokenSourceFixer
  record LineInfo,
    line_index : Int32,
    indent : Int32,
    keyword : String

  def self.fix(source : String) : String
    stack = [] of LineInfo

    lines = source.lines
    lines.each_with_index do |line, line_index|
      next if line.blank?

      keyword = line_keyword(line)
      indent = line_indent(line)

      while true
        last_info = stack.last?
        # Check if this line has less indent than the indent
        # for the last opening keyword we found.
        if last_info &&
           (indent < last_info.indent ||
           indent == last_info.indent && keyword != "end")
          # If that's the case we fix the opening keyword by
          # adding an "end" to it.
          last_line = lines[line_index - 1]

          lines[line_index - 1] =
            if last_line.blank?
              # If the line is empty we can change it to an end
              # and even use the correct indent.
              last_line = ("  " * last_info.indent) + "end"
            else
              last_line + "; end"
            end

          stack.pop
        else
          # If that's not the case we are still keeping a good indent.
          break
        end
      end

      # If we found an "end" at exactly the indentation of the last
      # opening keyword, remove it from the stack.
      if keyword == "end" && indent == last_info.try(&.indent)
        # all good: an end is closing an opening keyword
        stack.pop
        next
      end

      # Push to the stack if we found an opening keyword.
      if keyword && keyword != "end"
        stack << LineInfo.new(
          line_index: line_index,
          indent: indent,
          keyword: keyword
        )
      end
    end

    until stack.empty?
      lines[-1] = lines[-1] + "; end"
      stack.pop
    end

    lines.join("\n")
  end

  def self.line_indent(line : String) : Int32?
    non_whitespace_char_index = line.each_char_with_index do |char, i|
      next if char.whitespace?
      break i
    end

    if non_whitespace_char_index
      non_whitespace_char_index // 2
    else
      0
    end
  end

  def self.line_keyword(line : String) : String?
    if line.starts_with?(/\s*if\s/)
      "if"
    elsif line.starts_with?(/\s*def\s/)
      "def"
    elsif line.starts_with?(/\s*end\s*$/)
      "end"
    else
      nil
    end
  end

  def self.check
    last_info = stack.last?
    if last_info && indent < last_info.indent
      if keyword == "end" && indent == last_info.indent
        # All good: an end is closing an opening keyword
        stack.pop
        next
      end

      lines[line_index - 1] = lines[line_index - 1] + "; end"
      stack.pop
    end
  end
end
