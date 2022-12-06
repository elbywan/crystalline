class Crystalline::BrokenSourceFixer
  # Keep track of opening and closing keywords, and their idents,
  # as they happen in the code.
  record LineInfo,
    line_index : Int32,
    indent : Int32,
    keyword : String

  # Try to fix a broken source code by adding missing "end" and "}"
  # according to indentation.
  def self.fix(source : String) : String
    # Keep a stack of opening keywords.
    # We push to the stack when we find an opening keyword and
    # we pop from the stack when we find a closing keyword,
    # or when we find a wrong indentation.
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
        if wrong_indent?(indent, keyword, closing_keyword, last_info, line)
          # If that's the case we fix the opening keyword by
          # adding an "end" to it.
          last_line = lines[line_index - 1]

          lines[line_index - 1] =
            if last_line.blank?
              # If the line is empty we can change it to an end
              # and even use the correct indent.
              "#{("  " * last_info.indent)}#{closing_keyword}"
            else
              "#{last_line}; #{closing_keyword}"
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

    while line_info = stack.pop?
      lines[-1] = "#{lines[-1]}; #{closing_keyword(line_info)}"
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
    if line.starts_with?(/\s*
      (
        if |
        unless |
        while |
        until |
        ((private|protected)\s+)?def |
        (private\s+)?(abstract\s+)?class |
        (private\s+)?(abstract\s+)?struct |
        (private\s+)?module |
        (private\s+)?enum |
        (private\s+)?annotation
      )\s/x)
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
    last_info : LineInfo,
    line : String
  )
    # If the indent is less than the opening one it's definitely wrong.
    if indent < last_info.indent
      return true
    end

    # If the indent is greater, it's all good (it's probably content inside that definition)
    if indent > last_info.indent
      return false
    end

    # All good if it's the closing keyword to an opening definition
    if keyword == closing_keyword
      return false
    end

    # Some special cases: else and elsif have the same indentation as
    # the opening keyword but they don't close it (more content is expected
    # to come until the "end" keyword)
    if last_info.keyword == "if" && keyword == "else"
      return false
    end

    if last_info.keyword == "if" && keyword == "elsif"
      return false
    end

    if last_info.keyword == "unless" && keyword == "else"
      return false
    end

    # A def signature can also be defined in multiple lines, like this:
    #
    # def foo(
    #   x, y
    # )
    #
    # In that case we don't want to consider the closing parentheses
    # as having wrong indentation.
    if last_info.keyword == "def" && line.strip == ")"
      return false
    end

    true
  end
end
