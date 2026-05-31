module Crystalline::Lightweight::TypeUtils
  extend self

  def substitute_generic_params(value : String, mapping : Hash(String, String)) : String
    return value if mapping.empty?

    String.build do |result|
      index = 0
      while index < value.size
        char = value[index]

        if char == '*' && (next_char = value[index + 1]?) && token_start_char?(next_char)
          token_end = token_end_index(value, index + 1)
          token = value[index..token_end]
          result << (mapping[token]? || token)
          index = token_end + 1
        elsif token_start_char?(char)
          token_end = token_end_index(value, index)
          token = value[index..token_end]
          result << (mapping[token]? || token)
          index = token_end + 1
        else
          result << char
          index += 1
        end
      end
    end
  end

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

  private def token_start_char?(char : Char) : Bool
    char.ascii_letter? || char == '_'
  end

  private def token_end_index(value : String, start_index : Int32) : Int32
    index = start_index
    while (char = value[index + 1]?) && (char.ascii_alphanumeric? || char.in?('_', '?', '!'))
      index += 1
    end
    index
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
