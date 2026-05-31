module Crystalline::Lightweight::TypeUtils
  extend self

  def expand_type_names(type_name : String) : Array(String)
    normalized = unwrap_outer_parens(type_name.strip)
    parts = split_top_level(normalized, '|')
    parts.empty? ? [normalized] : parts
  end

  def split_top_level(value : String, delimiter : Char) : Array(String)
    parts = [] of String
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0
    start = 0

    value.each_char_with_index do |char, index|
      case char
      when '('
        paren_depth += 1
      when ')'
        paren_depth -= 1 if paren_depth > 0
      when '{'
        brace_depth += 1
      when '}'
        brace_depth -= 1 if brace_depth > 0
      when '['
        bracket_depth += 1
      when ']'
        bracket_depth -= 1 if bracket_depth > 0
      when delimiter
        next unless paren_depth == 0 && brace_depth == 0 && bracket_depth == 0

        parts << value[start...index].strip
        start = index + 1
      end
    end

    parts << value[start..].to_s.strip
    parts.reject(&.empty?)
  end

  private def unwrap_outer_parens(value : String) : String
    return value unless value.starts_with?('(') && value.ends_with?(')')
    return value unless wraps_whole_expression?(value)

    value[1...-1]
  end

  private def wraps_whole_expression?(value : String) : Bool
    depth = 0

    value.each_char_with_index do |char, index|
      case char
      when '('
        depth += 1
      when ')'
        depth -= 1
        return false if depth == 0 && index < value.size - 1
      end
    end

    depth == 0
  end
end
