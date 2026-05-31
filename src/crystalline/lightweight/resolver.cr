require "./inference"
require "./type_utils"
require "./query"

module Crystalline::Lightweight
  module Resolver
    extend self

    def receiver_types(source : String, line_number : Int32, analysis_column : Int32, receiver : String, query : Query) : {Array(String), Bool}
      segments = receiver.split('.')
      return {[] of String, false} if segments.empty?

      type_names, class_method = root_receiver_types(source, line_number, analysis_column, segments.shift, query)
      return {[] of String, class_method} if type_names.empty?

      segments.each do |segment|
        type_names, class_method = chained_call_types(type_names, class_method, segment, query)
        return {[] of String, class_method} if type_names.empty?
      end

      {type_names, class_method}
    end

    def receiver_from_prefix(prefix : String) : String
      start = prefix.size

      while start > 0 && receiver_expression_char?(prefix[start - 1])
        start -= 1
      end

      prefix[start..]? || ""
    end

    def receiver_expression_char?(char : Char)
      token_char?(char) || char == '.'
    end

    def token_char?(char : Char)
      char.ascii_alphanumeric? || char.in?('_', '?', '!', '@', ':')
    end

    def instance_var_name?(name : String)
      !!(name =~ /\A@[a-zA-Z_][a-zA-Z0-9_?!]*\z/)
    end

    def class_var_name?(name : String)
      !!(name =~ /\A@@[a-zA-Z_][a-zA-Z0-9_?!]*\z/)
    end

    def local_name?(name : String)
      !!(name =~ /\A[a-z_][a-zA-Z0-9_?!]*\z/)
    end

    def type_name?(name : String)
      !!(name =~ /\A[A-Z][a-zA-Z0-9_]*(?:::[A-Z][a-zA-Z0-9_]*)*\z/)
    end

    private def root_receiver_types(source : String, line_number : Int32, analysis_column : Int32, receiver : String, query : Query) : {Array(String), Bool}
      inference = Inference.for(
        source,
        line_number + 1,
        analysis_column + 1,
        query,
      )

      if type_name?(receiver)
        resolved_name = query.resolve_type_name(receiver, namespace: inference.try(&.current_type_name))
        return {[resolved_name], true} if resolved_name
        return {[] of String, true}
      end

      if receiver == "self"
        return inference.try(&.self_types) || {[] of String, false}
      end

      if instance_var_name?(receiver)
        return {
          (inference ? inference.types_for_instance_var(receiver) : [] of String).select { |type_name| receiver_type_known?(type_name, query) },
          false,
        }
      end

      if class_var_name?(receiver)
        return {
          (inference ? inference.types_for_class_var(receiver) : [] of String).select { |type_name| receiver_type_known?(type_name, query) },
          true,
        }
      end

      return {[] of String, false} unless local_name?(receiver)

      if inference
        local_types = inference.types_for(receiver).select { |type_name| receiver_type_known?(type_name, query) }
        return {local_types, false} unless local_types.empty?
      end

      {
        query.top_level_methods.select { |method| method.name == receiver && method.args.empty? }.flat_map { |method|
          return_type_names(method.return_type, query)
        }.uniq,
        false,
      }
    end

    private def chained_call_types(type_names : Array(String), class_method : Bool, method_name : String, query : Query) : {Array(String), Bool}
      if class_method
        valid_types = type_names.select { |type_name| receiver_type_known?(type_name, query) }.uniq
        return {valid_types, false} if method_name == "new"
        return {valid_types, true} if method_name == "class"
      elsif method_name == "class"
        return {type_names.select { |type_name| receiver_type_known?(type_name, query) }.uniq, true}
      end

      special_types = type_names.flat_map { |type_name| special_return_type_names(type_name, method_name, query) }.uniq
      return {special_types, false} unless special_types.empty?

      return_types = type_names.flat_map do |type_name|
        query.methods_for(type_name, class_method: class_method).select { |method|
          method.name == method_name && method.args.empty?
        }.flat_map do |method|
          return_type_names(method.return_type, query)
        end
      end

      {return_types.uniq, false}
    end

    private def receiver_type_known?(type_name : String, query : Query) : Bool
      query.find_type(type_name) != nil ||
        array_element_types(type_name) != nil ||
        hash_value_types(type_name) != nil ||
        tuple_element_types(type_name) != nil ||
        named_tuple_known?(type_name)
    end

    private def special_return_type_names(type_name : String, method_name : String, query : Query) : Array(String)
      if contracts = query.method_contracts_for(type_name, method_name)
        contract_types = [] of String
        contracts.each do |contract|
          case contract.kind
          when .preserve_receiver?
            contract_types.concat(contract.types)
          when .return_element?, .return_value?
            contract_types.concat(contract.types)
          when .return_element_or_nil?, .return_value_or_nil?
            contract_types.concat(contract.types)
            contract_types << "Nil"
          end
        end
        contract_types = contract_types.uniq
        return contract_types unless contract_types.empty?
      end

      case method_name
      when "not_nil!"
        return normalize_type_names(type_name).reject(&.==("Nil"))
      when "tap", "each", "each_with_index", "select", "reject"
        return [type_name]
      when "first", "last", "[]", "find!", "reduce"
        if element_types = array_element_types(type_name)
          return element_types.select { |item| receiver_type_known?(item, query) || query.find_type(item) != nil }
        elsif tuple_types = tuple_element_types(type_name)
          if method_name == "first"
            return tuple_types.first? || [] of String
          elsif method_name == "last"
            return tuple_types.last? || [] of String
          end
          return tuple_types.flatten.uniq
        elsif value_types = hash_value_types(type_name)
          return value_types.select { |item| receiver_type_known?(item, query) || query.find_type(item) != nil }
        end
      when "first?", "last?", "[]?", "find", "dig"
        if element_types = array_element_types(type_name)
          return (element_types + ["Nil"]).uniq
        elsif tuple_types = tuple_element_types(type_name)
          selected = if method_name == "first?"
            tuple_types.first? || [] of String
          elsif method_name == "last?"
            tuple_types.last? || [] of String
          else
            tuple_types.flatten.uniq
          end
          return (selected + ["Nil"]).uniq
        elsif value_types = hash_value_types(type_name)
          return (value_types + ["Nil"]).uniq
        elsif value_types = named_tuple_all_value_types(type_name)
          return (value_types + ["Nil"]).uniq
        end
      when "fetch"
        if value_types = hash_value_types(type_name)
          return value_types
        end
      else
        if value_types = named_tuple_value_types(type_name, method_name)
          return value_types.select { |item| receiver_type_known?(item, query) || query.find_type(item) != nil }
        end
      end

      [] of String
    end

    private def return_type_names(return_type : String?, query : Query) : Array(String)
      return [] of String unless return_type

      normalize_type_names(return_type).select { |type_name| receiver_type_known?(type_name, query) || query.find_type(type_name) != nil }
    end

    private def normalize_type_names(type_name : String) : Array(String)
      TypeUtils.expand_type_names(type_name)
    end

    private def array_element_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Array", 1).try { |parts| normalize_type_names(parts[0]) }
    end

    private def hash_value_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Hash", 2).try { |parts| normalize_type_names(parts[1]) }
    end

    private def named_tuple_all_value_types(type_name : String) : Array(String)?
      normalized = type_name.strip
      prefix = "NamedTuple("
      return unless normalized.starts_with?(prefix) && normalized.ends_with?(')')

      value_types = split_top_level(normalized[prefix.size...-1]).flat_map do |part|
        _, value = part.split(":", 2)
        next [] of String unless value
        normalize_type_names(value.strip)
      end.uniq

      value_types.empty? ? nil : value_types
    end

    private def tuple_element_types(type_name : String) : Array(Array(String))?
      generic_type_arguments(type_name, "Tuple", nil).try { |parts| parts.map { |part| normalize_type_names(part) } }
    end

    private def named_tuple_value_types(type_name : String, field_name : String) : Array(String)?
      normalized = type_name.strip
      prefix = "NamedTuple("
      return unless normalized.starts_with?(prefix) && normalized.ends_with?(')')

      split_top_level(normalized[prefix.size...-1]).each do |part|
        key, value = part.split(":", 2)
        next unless value
        return normalize_type_names(value.strip) if key.strip == field_name
      end

      nil
    end

    private def named_tuple_known?(type_name : String) : Bool
      normalized = type_name.strip
      normalized.starts_with?("NamedTuple(") && normalized.ends_with?(')')
    end

    private def generic_type_arguments(type_name : String, generic_name : String, arity : Int32?) : Array(String)?
      normalized = type_name.strip
      prefix = "#{generic_name}("
      return unless normalized.starts_with?(prefix) && normalized.ends_with?(')')

      parts = split_top_level(normalized[prefix.size...-1])
      return unless arity.nil? || parts.size == arity

      parts
    end

    private def split_top_level(value : String) : Array(String)
      parts = [] of String
      depth = 0
      start = 0

      value.each_char_with_index do |char, index|
        case char
        when '('
          depth += 1
        when ')'
          depth -= 1 if depth > 0
        when ','
          if depth == 0
            parts << value[start...index].strip
            start = index + 1
          end
        end
      end

      parts << value[start..].to_s.strip
      parts.reject(&.empty?)
    end
  end
end
