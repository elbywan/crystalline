require "./type_utils"

module Crystalline::Lightweight
  enum MethodContractKind
    YieldSelf
    YieldElement
    YieldElementWithIndex
    YieldKey
    YieldValue
    YieldKeyValue
    YieldAccumulatorAndElement
    PreserveReceiver
    ReturnElement
    ReturnElementOrNil
    ReturnValue
    ReturnValueOrNil
  end

  record MethodContract,
    kind : MethodContractKind,
    types : Array(String) = [] of String,
    block_args : Array(Array(String)) = [] of Array(String),
    class_method : Bool = false

  class SummaryType
    getter name : String
    getter methods = [] of MethodInfo
    getter method_contracts = {} of String => Array(MethodContract)
    getter instance_vars = {} of String => Array(String)
    getter class_vars = {} of String => Array(String)

    def initialize(@name : String)
    end
  end

  class Summary
    getter types = {} of String => SummaryType

    def self.from_result(result : Crystal::Compiler::Result) : self
      new.tap do |summary|
        summary.process_type(result.program)
      end
    end

    def type(name : String) : SummaryType?
      @types[name]?
    end

    protected def process_type(type : Crystal::Type)
      if type.is_a?(Crystal::NamedType) || type.is_a?(Crystal::Program) || type.is_a?(Crystal::FileModule)
        type.types?.try &.each_value do |inner_type|
          process_type(inner_type)
        end
      end

      if type.is_a?(Crystal::GenericType)
        type.each_instantiated_type do |instance|
          process_type(instance)
        end
      end

      summarize_type(type)
      process_type(type.metaclass) if type.metaclass != type

      if type.is_a?(Crystal::DefInstanceContainer)
        type.def_instances.each_value do |typed_def|
          summarize_typed_def(type, typed_def)
        end
      end
    end

    private def summarize_type(type : Crystal::Type)
      return unless type.is_a?(Crystal::NamedType)

      summary_type = ensure_type(type.to_s)

      begin
        if type.allows_instance_vars?
          type.all_instance_vars.each do |name, ivar|
            summary_type.instance_vars[name] = expand_type_names(ivar.type.to_s)
          end
        end
      rescue
      end

      metaclass = type.metaclass
      if metaclass.is_a?(Crystal::MetaclassType)
        begin
          metaclass.all_class_vars.each do |name, cvar|
            summary_type.class_vars[name] = expand_type_names(cvar.type.to_s)
          end
        rescue
        end
      end
    end

    private def summarize_typed_def(type : Crystal::Type, typed_def : Crystal::Def)
      owner_name, class_method = owner_info(type)
      return_type = typed_def.type?.try(&.to_s) || typed_def.body.type?.try(&.to_s)
      return unless return_type

      summary_type = ensure_type(owner_name)
      method = MethodInfo.new(
        name: typed_def.name.to_s,
        owner: owner_name,
        args: typed_def.args.map { |arg|
          restriction = arg.type?.try(&.to_s) || arg.restriction.try(&.to_s)
          ArgInfo.new(name: arg.name.to_s, restriction: restriction)
        },
        return_type: return_type,
        class_method: class_method,
        doc: typed_def.doc,
        location: typed_def.location,
        name_location: typed_def.name_location,
        name_size: typed_def.name.to_s.size,
      )

      existing_index = summary_type.methods.index do |existing|
        existing.name == method.name &&
          existing.class_method == method.class_method &&
          existing.args.map(&.restriction) == method.args.map(&.restriction)
      end

      if existing_index
        summary_type.methods[existing_index] = method
      else
        summary_type.methods << method
      end

      contracts = summary_type.method_contracts[method.name] ||= [] of MethodContract
      infer_contracts(owner_name, method).each do |contract|
        contracts << contract unless contracts.includes?(contract)
      end
    end

    private def infer_contracts(owner_name : String, method : MethodInfo) : Array(MethodContract)
      contracts = [] of MethodContract
      return contracts unless return_type = method.return_type

      normalized_return_types = expand_type_names(return_type)

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
        when "each", "map", "select", "reject", "find", "compact_map", "flat_map"
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

    private def owner_info(type : Crystal::Type) : {String, Bool}
      if type.is_a?(Crystal::MetaclassType)
        {type.instance_type.to_s, true}
      else
        {type.to_s, false}
      end
    end

    private def ensure_type(name : String) : SummaryType
      @types[name] ||= SummaryType.new(name)
    end

    private def array_element_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Array", 1).try { |parts| expand_type_names(parts[0]) }
    end

    private def hash_key_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Hash", 2).try { |parts| expand_type_names(parts[0]) }
    end

    private def hash_value_types(type_name : String) : Array(String)?
      generic_type_arguments(type_name, "Hash", 2).try { |parts| expand_type_names(parts[1]) }
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

    private def expand_type_names(type_name : String) : Array(String)
      TypeUtils.expand_type_names(type_name)
    end
  end
end
