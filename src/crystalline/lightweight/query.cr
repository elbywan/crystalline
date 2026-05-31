require "./index"
require "./summary"

module Crystalline::Lightweight
  class Query
    def initialize(@index : Index, @summary : Summary? = nil)
    end

    def find_type(name : String) : TypeInfo?
      @index.types[name]?
    end

    def methods_for(type_name : String, *, class_method = false, include_macros = false) : Array(MethodInfo)
      methods = [] of MethodInfo

      if type = find_type(type_name)
        methods.concat(type.methods.select do |method|
          method.class_method == class_method && (include_macros || !method.macro)
        end)
      end

      if summary_type = @summary.try &.type(type_name)
        methods = merge_methods(methods, summary_type.methods.select(&.class_method.==(class_method)))
      end

      methods
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
      contracts = @summary.try(&.type(type_name)).try(&.method_contracts[method_name]?).try(&.select(&.class_method.==(class_method))).try(&.dup) || [] of MethodContract

      methods_for(type_name, class_method: class_method).select(&.name.==(method_name)).each do |method|
        infer_contracts(type_name, method).each do |contract|
          contracts << contract unless contracts.includes?(contract)
        end
      end

      contracts
    end

    def instance_var_types_for(type_name : String, var_name : String) : Array(String)
      @summary.try(&.type(type_name)).try(&.instance_vars[var_name]?) || [] of String
    end

    def class_var_types_for(type_name : String, var_name : String) : Array(String)
      @summary.try(&.type(type_name)).try(&.class_vars[var_name]?) || [] of String
    end

    def instance_vars_for(type_name : String) : Hash(String, Array(String))
      @summary.try(&.type(type_name)).try(&.instance_vars.transform_values(&.dup)) || {} of String => Array(String)
    end

    def class_vars_for(type_name : String) : Hash(String, Array(String))
      @summary.try(&.type(type_name)).try(&.class_vars.transform_values(&.dup)) || {} of String => Array(String)
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
        when "each", "map", "select", "reject", "compact_map"
          contracts << MethodContract.new(kind: MethodContractKind::YieldElement, types: element_types, class_method: method.class_method)
        when "each_with_index", "map_with_index"
          contracts << MethodContract.new(kind: MethodContractKind::YieldElementWithIndex, types: element_types + ["Int32"], class_method: method.class_method)
        end

        if normalized_return_types.sort == element_types.sort
          contracts << MethodContract.new(kind: MethodContractKind::ReturnElement, types: element_types, class_method: method.class_method)
        elsif normalized_return_types.sort == (element_types + ["Nil"]).uniq.sort
          contracts << MethodContract.new(kind: MethodContractKind::ReturnElementOrNil, types: element_types, class_method: method.class_method)
        end
      end

      if value_types = hash_value_types(owner_name)
        if normalized_return_types.sort == value_types.sort
          contracts << MethodContract.new(kind: MethodContractKind::ReturnValue, types: value_types, class_method: method.class_method)
        elsif normalized_return_types.sort == (value_types + ["Nil"]).uniq.sort
          contracts << MethodContract.new(kind: MethodContractKind::ReturnValueOrNil, types: value_types, class_method: method.class_method)
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
      normalized = type_name.strip
      normalized = normalized[1...-1] if normalized.starts_with?('(') && normalized.ends_with?(')')
      normalized.includes?(" | ") ? normalized.split(" | ").map(&.strip).reject(&.empty?).uniq : [normalized]
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
          )
        else
          merged << summary_method
        end
      end

      merged
    end
  end
end
