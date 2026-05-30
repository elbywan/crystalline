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
