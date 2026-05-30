module Crystalline::Lightweight
  class SummaryType
    getter name : String
    getter methods = [] of MethodInfo
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

    private def expand_type_names(type_name : String) : Array(String)
      normalized = type_name.strip
      normalized = normalized[1...-1] if normalized.starts_with?('(') && normalized.ends_with?(')')
      return [normalized] unless normalized.includes?(" | ")

      normalized.split(" | ").map(&.strip).reject(&.empty?).uniq
    end
  end
end
