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
        break unless last_info

        closing_keyword = closing_keyword(last_info)

        # Check if this line has less indent than the indent
        # for the last opening keyword we found.
        if wrong_indent?(indent, keyword, closing_keyword, last_info)
          # If that's the case we fix the opening keyword by
          # adding an "end" to it.
          last_line = lines[line_index - 1]

          lines[line_index - 1] =
            if last_line.blank?
              # If the line is empty we can change it to an end
              # and even use the correct indent.
              last_line = ("  " * last_info.indent) + closing_keyword
            else
              last_line + "; " + closing_keyword
            end

          stack.pop
        else
          # If that's not the case we are still keeping a good indent.
          break
        end
      end

      # If we found an "end" at exactly the indentation of the last
      # opening keyword, remove it from the stack.
      if last_info && indent == last_info.indent && keyword == closing_keyword(last_info)
        # all good: an end is closing an opening keyword
        stack.pop
        next
      end

      # Push to the stack if we found an opening keyword.
      if keyword && keyword != "end" && keyword != "}" && keyword != "else" && keyword != "elsif"
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

  private def self.line_indent(line : String) : Int32?
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

  private def self.line_keyword(line : String) : String?
    if line.starts_with?(/\s*(if|unless|while|until|def|class|struct|module|enum|annotation)\s/)
      $1
    elsif line.ends_with?(/\s*do(\s+\|[^|]+\|)?\s*$/)
      "do"
    elsif line.ends_with?(/\s*\)\s*{(\s*\|[^|]+\|)?\s*$/)
      "{"
    elsif line.ends_with?(/\s*[\w\d]\s*{(\s*\|[^|]+\|)?\s*$/)
      "{"
    elsif line.matches?(/\s*end\s*$/)
      "end"
    elsif line.matches?(/\s*}\s*$/)
      "}"
    elsif line.matches?(/\s*else\s*$/)
      "else"
    elsif line.starts_with?(/\s*elsif\s+/)
      "elsif"
    else
      nil
    end
  end

  private def self.closing_keyword(line_info : LineInfo)
    closing_keyword(line_info.keyword)
  end

  private def self.closing_keyword(keyword : String)
    keyword == "{" ? "}" : "end"
  end

  private def self.wrong_indent?(
    indent : Int32,
    keyword : String?,
    closing_keyword : String?,
    last_info : LineInfo
  )
    return true if indent < last_info.indent

    indent == last_info.indent &&
      keyword != closing_keyword &&
      !(last_info.keyword == "if" && keyword == "else") &&
      !(last_info.keyword == "if" && keyword == "elsif") &&
      !(last_info.keyword == "unless" && keyword == "else")
  end
end
