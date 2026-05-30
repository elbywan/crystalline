require "./lightweight_index"

module Crystalline::Lightweight
  class Query
    def initialize(@index : Index)
    end

    def find_type(name : String) : TypeInfo?
      @index.types[name]?
    end

    def methods_for(type_name : String, *, class_method = false, include_macros = false) : Array(MethodInfo)
      type = find_type(type_name)
      return [] of MethodInfo unless type

      type.methods.select do |method|
        method.class_method == class_method && (include_macros || !method.macro)
      end
    end

    def subtypes_for(type_name : String) : Array(String)
      find_type(type_name).try(&.subtypes.dup) || [] of String
    end

    def top_level_methods : Array(MethodInfo)
      @index.top_level_methods.dup
    end
  end
end
