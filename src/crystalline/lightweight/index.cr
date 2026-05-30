module Crystalline::Lightweight
  enum TypeKind
    Class
    Module
    Struct
    Enum
    Annotation
    Alias
    Lib
    Unknown
  end

  record ArgInfo, name : String, restriction : String?

  record MethodInfo,
    name : String,
    owner : String,
    args : Array(ArgInfo),
    return_type : String?,
    class_method : Bool = false,
    macro : Bool = false,
    doc : String? = nil

  class TypeInfo
    getter name : String
    getter kind : TypeKind
    getter doc : String?
    getter methods = [] of MethodInfo
    getter subtypes = [] of String

    def initialize(@name : String, @kind : TypeKind, @doc : String? = nil)
    end
  end

  class Index
    getter types = {} of String => TypeInfo
    getter top_level_methods = [] of MethodInfo

    def self.from_program(program : Crystal::Program) : self
      new.tap do |index|
        program.types.each_value do |type|
          index.index_type(type)
        end

        if defs = program.defs
          defs.each_value do |items|
            items.each do |item|
              index.top_level_methods << index.method_info_for(item.def, owner: "::")
            end
          end
        end
      end
    end

    protected def index_type(type : Crystal::NamedType)
      type_name = type.to_s
      type_info = (@types[type_name] ||= TypeInfo.new(type_name, kind_for(type), type.doc))

      if defs = type.defs
        defs.each_value do |items|
          items.each do |item|
            type_info.methods << method_info_for(item.def, owner: type_name)
          end
        end
      end

      if type.is_a?(Crystal::ModuleType)
        if macros = type.macros
          macros.each_value do |items|
            items.each do |macro_def|
              type_info.methods << method_info_for(macro_def, owner: type_name, is_macro: true)
            end
          end
        end
      end

      if metaclass = type.metaclass
        if defs = metaclass.defs
          defs.each_value do |items|
            items.each do |item|
              type_info.methods << method_info_for(item.def, owner: type_name, class_method: true)
            end
          end
        end
      end

      if nested_types = type.types?
        nested_types.each_value do |nested_type|
          type_info.subtypes << nested_type.to_s unless type_info.subtypes.includes?(nested_type.to_s)
          index_type(nested_type)
        end
      end
    end

    protected def method_info_for(definition : Crystal::Def | Crystal::Macro, *, owner : String, class_method = false, is_macro = false)
      args = definition.args.map do |arg|
        ArgInfo.new(name: arg.name.to_s, restriction: arg.restriction.try(&.to_s))
      end

      MethodInfo.new(
        name: definition.name.to_s,
        owner: owner,
        args: args,
        return_type: definition.responds_to?(:return_type) ? definition.return_type.try(&.to_s) : nil,
        class_method: class_method,
        macro: is_macro,
        doc: definition.doc,
      )
    end

    protected def kind_for(type : Crystal::NamedType)
      case type
      when Crystal::AnnotationType
        TypeKind::Annotation
      when Crystal::AliasType
        TypeKind::Alias
      when Crystal::EnumType
        TypeKind::Enum
      when Crystal::LibType
        TypeKind::Lib
      when Crystal::ClassType
        type.struct? ? TypeKind::Struct : TypeKind::Class
      when Crystal::ModuleType
        TypeKind::Module
      else
        TypeKind::Unknown
      end
    end
  end
end
