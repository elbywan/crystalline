require "./index"
require "./type_utils"
require "./summary"

module Crystalline::Lightweight
  class Query
    def initialize(@index : Index, @summary : Summary? = nil)
    end

    def find_type(name : String) : TypeInfo?
      @index.types[name]? || generic_specialization_for(name).try(&.[0])
    end

    def resolve_type_name(name : String, namespace : String? = nil) : String?
      normalized = name.strip
      normalized = normalized.lchop("::")
      return normalized if known_type_name?(normalized)

      if namespace
        namespace_candidates(namespace).each do |prefix|
          candidate = "#{prefix}::#{normalized}"
          return candidate if known_type_name?(candidate)
        end
      end

      suffix_matches = all_type_names.select do |candidate|
        candidate == normalized || candidate.ends_with?("::#{normalized}")
      end
      suffix_matches.size == 1 ? suffix_matches.first : nil
    end

    def methods_for(type_name : String, *, class_method = false, include_macros = false) : Array(MethodInfo)
      methods_for(type_name, class_method: class_method, include_macros: include_macros, visited: Set(String).new)
    end

    def subtypes_for(type_name : String) : Array(String)
      find_type(type_name).try(&.subtypes.dup) || [] of String
    end

    def top_level_methods : Array(MethodInfo)
      @index.top_level_methods.dup
    end

    def all_types : Array(TypeInfo)
      @index.types.values.to_a
    end

    def method_contracts_for(type_name : String, method_name : String, *, class_method = false) : Array(MethodContract)
      contracts = [] of MethodContract
      summary_types_for(type_name).each do |summary_type|
        summary_type.method_contracts[method_name]?.try(&.each do |contract|
          next unless contract.class_method == class_method
          contracts << contract unless contracts.includes?(contract)
        end)
      end

      methods_for(type_name, class_method: class_method).select(&.name.==(method_name)).each do |method|
        infer_contracts(type_name, method).each do |contract|
          contracts << contract unless contracts.includes?(contract)
        end
      end

      contracts
    end

    def instance_var_types_for(type_name : String, var_name : String) : Array(String)
      summary_types_for(type_name).each do |summary_type|
        if types = summary_type.instance_vars[var_name]?
          return types
        end
      end
      [] of String
    end

    def class_var_types_for(type_name : String, var_name : String) : Array(String)
      summary_types_for(type_name).each do |summary_type|
        if types = summary_type.class_vars[var_name]?
          return types
        end
      end
      [] of String
    end

    def instance_vars_for(type_name : String) : Hash(String, Array(String))
      summary_types_for(type_name).each do |summary_type|
        return summary_type.instance_vars.transform_values(&.dup) if summary_type.instance_vars.any?
      end
      {} of String => Array(String)
    end

    def class_vars_for(type_name : String) : Hash(String, Array(String))
      summary_types_for(type_name).each do |summary_type|
        return summary_type.class_vars.transform_values(&.dup) if summary_type.class_vars.any?
      end
      {} of String => Array(String)
    end

    private def known_type_name?(name : String) : Bool
      @index.types.has_key?(name) || !generic_specialization_for(name).nil?
    end

    private def all_type_names : Array(String)
      names = @index.types.keys
      if summary = @summary
        names += summary.types.keys
      end
      names.uniq
    end

    private def namespace_candidates(namespace : String) : Array(String)
      parts = namespace.split("::")
      candidates = [] of String
      while parts.any?
        candidates << parts.join("::")
        parts.pop
      end
      candidates
    end

    private def summary_types_for(type_name : String) : Array(SummaryType)
      types = [] of SummaryType
      if summary_type = @summary.try(&.type(type_name))
        types << summary_type
      end

      if specialization = generic_summary_specialization_for(type_name)
        summary_type, _ = specialization
        types << summary_type unless types.includes?(summary_type)
      end

      types
    end

    private def methods_for(type_name : String, *, class_method : Bool, include_macros : Bool, visited : Set(String)) : Array(MethodInfo)
      visit_key = "#{type_name}:#{class_method}:#{include_macros}"
      return [] of MethodInfo if visited.includes?(visit_key)
      visited << visit_key

      methods = [] of MethodInfo
      parent_types = [] of String

      if type = @index.types[type_name]?
        methods.concat(type.methods.select do |method|
          method.class_method == class_method && (include_macros || !method.macro)
        end)
        parent_types = type.parent_types.dup
      elsif specialization = generic_specialization_for(type_name)
        generic_type, mapping = specialization
        methods.concat(generic_type.methods.select { |method|
          method.class_method == class_method && (include_macros || !method.macro)
        }.map { |method|
          specialize_method(method, owner_name: type_name, mapping: mapping)
        })
        parent_types = generic_type.parent_types.map do |parent_type|
          substitute_type_vars(parent_type, mapping).not_nil!
        end
      elsif type = find_type(type_name)
        methods.concat(type.methods.select do |method|
          method.class_method == class_method && (include_macros || !method.macro)
        end)
        parent_types = type.parent_types.dup
      end

      parent_types.each do |parent_type|
        methods = merge_methods(methods, methods_for(parent_type, class_method: class_method, include_macros: include_macros, visited: visited))
      end

      summary_types_for(type_name).each do |summary_type|
        methods = merge_methods(methods, summary_type.methods.select(&.class_method.==(class_method)))
      end

      methods
    end

    private def generic_specialization_for(type_name : String) : {TypeInfo, Hash(String, String)}?
      generic_specialization(type_name) do |candidate_name|
        @index.types[candidate_name]?
      end
    end

    private def generic_summary_specialization_for(type_name : String) : {SummaryType, Hash(String, String)}?
      generic_specialization(type_name) do |candidate_name|
        @summary.try(&.type(candidate_name))
      end
    end

    private def generic_specialization(type_name : String, &resolver : String -> T?) forall T
      normalized = type_name.strip
      return unless open_index = normalized.index('(')
      return unless normalized.ends_with?(')')

      base_name = normalized[0, open_index]
      actual_args = split_top_level(normalized[open_index + 1...-1])

      generic_candidate_names(base_name).each do |candidate_name|
        candidate_params = split_top_level(candidate_name[base_name.size + 1...-1])
        mapping = build_generic_mapping(candidate_params, actual_args)
        next unless mapping

        if candidate = yield candidate_name
          return {candidate, mapping}
        end
      end

      nil
    end

    private def build_generic_mapping(candidate_params : Array(String), actual_args : Array(String)) : Hash(String, String)?
      if candidate_params.size == actual_args.size
        mapping = {} of String => String
        candidate_params.each_with_index do |param, index|
          mapping[param] = actual_args[index]
        end
        return mapping
      end

      return unless candidate_params.size == 1
      splat_param = candidate_params.first
      return unless splat_param.starts_with?('*')

      union_value = actual_args.join(" | ")
      {
        splat_param => union_value,
      }
    end

    private def generic_candidate_names(base_name : String) : Array(String)
      candidates = @index.types.keys.select { |name| name.starts_with?("#{base_name}(") }
      if summary = @summary
        candidates.concat(summary.types.keys.select { |name| name.starts_with?("#{base_name}(") })
      end
      candidates.uniq
    end

    private def specialize_method(method : MethodInfo, owner_name : String, mapping : Hash(String, String)) : MethodInfo
      MethodInfo.new(
        name: method.name,
        owner: owner_name,
        args: method.args.map { |arg|
          ArgInfo.new(name: arg.name, restriction: substitute_type_vars(arg.restriction, mapping))
        },
        return_type: substitute_type_vars(method.return_type, mapping),
        class_method: method.class_method,
        macro: method.macro,
        doc: method.doc,
        location: method.location,
        name_location: method.name_location,
        name_size: method.name_size,
      )
    end

    private def substitute_type_vars(type_name : String?, mapping : Hash(String, String)) : String?
      return unless type_name

      mapping.reduce(type_name) do |value, (param, replacement)|
        value.gsub(/\b#{Regex.escape(param)}\b/, replacement)
      end
    end

    private def infer_contracts(owner_name : String, method : MethodInfo) : Array(MethodContract)
      contracts = [] of MethodContract
      return contracts unless return_type = method.return_type

      normalized_return_types = normalize_type_names(return_type)

      if normalized_return_types == [owner_name]
        contracts << MethodContract.new(kind: MethodContractKind::PreserveReceiver, types: [owner_name], class_method: method.class_method)
      elsif normalized_return_types.sort == [owner_name, "Nil"].sort
        contracts << MethodContract.new(kind: MethodContractKind::ReturnValueOrNil, types: [owner_name], class_method: method.class_method)
      elsif normalized_return_types.includes?("Nil")
        contracts << MethodContract.new(kind: MethodContractKind::ReturnValueOrNil, types: normalized_return_types.reject(&.==("Nil")), class_method: method.class_method)
      else
        contracts << MethodContract.new(kind: MethodContractKind::ReturnValue, types: normalized_return_types, class_method: method.class_method)
      end

      if element_types = array_element_types(owner_name)
        case method.name
        when "each", "map", "select", "reject", "find", "compact_map"
          contracts << MethodContract.new(kind: MethodContractKind::YieldElement, types: element_types, class_method: method.class_method)
        when "each_with_index", "map_with_index"
          contracts << MethodContract.new(kind: MethodContractKind::YieldElementWithIndex, types: element_types + ["Int32"], class_method: method.class_method)
        when "reduce"
          contracts << MethodContract.new(kind: MethodContractKind::YieldAccumulatorAndElement, block_args: [element_types, element_types], class_method: method.class_method)
        end

        case method.name
        when "each", "each_with_index", "select", "reject"
          contracts << MethodContract.new(kind: MethodContractKind::PreserveReceiver, types: [owner_name], class_method: method.class_method)
        when "first", "last", "[]", "find!"
          contracts << MethodContract.new(kind: MethodContractKind::ReturnElement, types: element_types, class_method: method.class_method)
        when "first?", "last?", "[]?", "find", "dig"
          contracts << MethodContract.new(kind: MethodContractKind::ReturnElementOrNil, types: element_types, class_method: method.class_method)
        when "reduce"
          contracts << MethodContract.new(kind: MethodContractKind::ReturnElement, types: element_types, class_method: method.class_method)
        end

        if normalized_return_types.sort == element_types.sort
          contracts << MethodContract.new(kind: MethodContractKind::ReturnElement, types: element_types, class_method: method.class_method)
        elsif normalized_return_types.sort == (element_types + ["Nil"]).uniq.sort
          contracts << MethodContract.new(kind: MethodContractKind::ReturnElementOrNil, types: element_types, class_method: method.class_method)
        end
      end

      if key_types = hash_key_types(owner_name)
        if value_types = hash_value_types(owner_name)
          case method.name
          when "each", "map", "select", "reject", "find", "compact_map"
            contracts << MethodContract.new(kind: MethodContractKind::YieldKeyValue, block_args: [key_types, value_types], class_method: method.class_method)
          when "each_key"
            contracts << MethodContract.new(kind: MethodContractKind::YieldKey, types: key_types, class_method: method.class_method)
          when "each_value"
            contracts << MethodContract.new(kind: MethodContractKind::YieldValue, types: value_types, class_method: method.class_method)
          end

          case method.name
          when "each", "select", "reject"
            contracts << MethodContract.new(kind: MethodContractKind::PreserveReceiver, types: [owner_name], class_method: method.class_method)
          when "[]", "fetch"
            contracts << MethodContract.new(kind: MethodContractKind::ReturnValue, types: value_types, class_method: method.class_method)
          when "[]?", "dig"
            contracts << MethodContract.new(kind: MethodContractKind::ReturnValueOrNil, types: value_types, class_method: method.class_method)
          end

          if normalized_return_types.sort == value_types.sort
            contracts << MethodContract.new(kind: MethodContractKind::ReturnValue, types: value_types, class_method: method.class_method)
          elsif normalized_return_types.sort == (value_types + ["Nil"]).uniq.sort
            contracts << MethodContract.new(kind: MethodContractKind::ReturnValueOrNil, types: value_types, class_method: method.class_method)
          end
        end
      end

      if method.name == "tap" && normalized_return_types == [owner_name]
        contracts << MethodContract.new(kind: MethodContractKind::YieldSelf, types: [owner_name], class_method: method.class_method)
      end

      contracts
    end

    private def array_element_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Array", 1).try { |parts| normalize_type_names(parts[0]) }
    end

    private def hash_key_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Hash", 2).try { |parts| normalize_type_names(parts[0]) }
    end

    private def hash_value_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Hash", 2).try { |parts| normalize_type_names(parts[1]) }
    end

    private def generic_type_arguments(type_name : String, generic_name : String, arity : Int32) : Array(String)?
      normalized = type_name.strip
      prefix = "#{generic_name}("
      return unless normalized.starts_with?(prefix) && normalized.ends_with?(')')

      parts = split_top_level(normalized[prefix.size...-1])
      return unless parts.size == arity

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

    private def normalize_type_names(type_name : String) : Array(String)
      TypeUtils.expand_type_names(type_name)
    end

    private def merge_methods(base_methods : Array(MethodInfo), summary_methods : Array(MethodInfo)) : Array(MethodInfo)
      merged = base_methods.dup

      summary_methods.each do |summary_method|
        index = merged.index do |method|
          method.name == summary_method.name &&
            method.class_method == summary_method.class_method &&
            method.args.map(&.restriction) == summary_method.args.map(&.restriction)
        end

        if index
          existing = merged[index]
          merged[index] = MethodInfo.new(
            name: existing.name,
            owner: existing.owner,
            args: existing.args.empty? ? summary_method.args : existing.args,
            return_type: summary_method.return_type || existing.return_type,
            class_method: existing.class_method,
            macro: existing.macro,
            doc: existing.doc || summary_method.doc,
            location: existing.location || summary_method.location,
            name_location: existing.name_location || summary_method.name_location,
            name_size: existing.name_size.zero? ? summary_method.name_size : existing.name_size,
          )
        else
          merged << summary_method
        end
      end

      merged
    end
  end
end
