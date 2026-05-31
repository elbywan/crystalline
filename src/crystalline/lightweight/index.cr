require "compiler/crystal/syntax"

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
    doc : String? = nil,
    location : Crystal::Location? = nil,
    name_location : Crystal::Location? = nil,
    name_size : Int32 = 0

  class TypeInfo
    getter name : String
    getter kind : TypeKind
    getter doc : String?
    getter methods = [] of MethodInfo
    getter subtypes = [] of String
    getter parent_types = [] of String

    def initialize(@name : String, @kind : TypeKind, @doc : String? = nil)
    end
  end

  class Index
    getter types = {} of String => TypeInfo
    getter top_level_methods = [] of MethodInfo

    def merge(other : Index) : Index
      merged = Index.new
      copy_into(merged, self)
      copy_into(merged, other)
      merged
    end

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

    def self.from_source(source : String) : self?
      parser = Crystal::Parser.new(source)
      parser.wants_doc = false
      ast = parser.parse

      new.tap do |index|
        index.index_syntax_node(ast)
      end
    rescue Crystal::SyntaxException
      nil
    end

    protected def copy_into(target : Index, source : Index)
      source.types.each_value do |type|
        target_type = target.types[type.name]?
        unless target_type
          target_type = TypeInfo.new(type.name, type.kind, type.doc)
          target.types[type.name] = target_type
        end

        type.methods.each do |method|
          next if target_type.methods.any? { |existing| same_method?(existing, method) }
          target_type.methods << method
        end

        type.subtypes.each do |subtype|
          target_type.subtypes << subtype unless target_type.subtypes.includes?(subtype)
        end

        type.parent_types.each do |parent_type|
          target_type.parent_types << parent_type unless target_type.parent_types.includes?(parent_type)
        end
      end

      source.top_level_methods.each do |method|
        next if target.top_level_methods.any? { |existing| same_method?(existing, method) }
        target.top_level_methods << method
      end
    end

    protected def same_method?(left : MethodInfo, right : MethodInfo) : Bool
      left.name == right.name &&
        left.owner == right.owner &&
        left.class_method == right.class_method &&
        left.macro == right.macro &&
        left.args.map(&.restriction) == right.args.map(&.restriction)
    end

    protected def index_syntax_node(node : Crystal::ASTNode, namespace : String? = nil)
      case node
      when Crystal::Expressions
        node.expressions.each { |expression| index_syntax_node(expression, namespace) }
      when Crystal::ClassDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        type_info = (@types[type_name] ||= TypeInfo.new(type_name, node.struct? ? TypeKind::Struct : TypeKind::Class, node.doc))
        index_syntax_type_body(type_info, node.body, type_name)
      when Crystal::ModuleDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        type_info = (@types[type_name] ||= TypeInfo.new(type_name, TypeKind::Module, node.doc))
        index_syntax_type_body(type_info, node.body, type_name)
      when Crystal::EnumDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        @types[type_name] ||= TypeInfo.new(type_name, TypeKind::Enum, node.doc)
      when Crystal::AnnotationDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        @types[type_name] ||= TypeInfo.new(type_name, TypeKind::Annotation, node.doc)
      when Crystal::Def
        return if node.receiver
        @top_level_methods << method_info_for(node, owner: "::")
      end
    end

    protected def index_syntax_type_body(type_info : TypeInfo, node : Crystal::ASTNode, type_name : String)
      case node
      when Crystal::Expressions
        node.expressions.each do |expression|
          case expression
          when Crystal::Def
            type_info.methods << method_info_for(expression, owner: type_name, class_method: !expression.receiver.nil?)
          when Crystal::ClassDef, Crystal::ModuleDef, Crystal::EnumDef, Crystal::AnnotationDef
            nested_name = qualify_type_name(expression.name.to_s, type_name)
            type_info.subtypes << nested_name unless type_info.subtypes.includes?(nested_name)
            index_syntax_node(expression, type_name)
          end
        end
      when Crystal::Def
        type_info.methods << method_info_for(node, owner: type_name, class_method: !node.receiver.nil?)
      end
    end

    protected def qualify_type_name(name : String, namespace : String?)
      return name if namespace.nil? || name.includes?("::")
      "#{namespace}::#{name}"
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

      type.parents.try &.each do |parent_type|
        parent_name = parent_type.to_s
        type_info.parent_types << parent_name unless type_info.parent_types.includes?(parent_name)
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
        location: definition.location,
        name_location: definition.responds_to?(:name_location) ? definition.name_location : nil,
        name_size: definition.name.to_s.size,
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
