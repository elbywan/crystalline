require "compiler/crystal/**"

module Crystalline
  class SubModuleVisitor < Crystal::Visitor
    getter submodules : Array(Crystal::ModuleType)

    def initialize(@target : Crystal::Type)
      @submodules = [] of Crystal::ModuleType
      @visited_types = Set(Crystal::Type).new
    end

    def process_result(result : Crystal::Compiler::Result)
      result.node.accept(self)
      result.program.file_modules.each_value { |file_module|
        process(file_module)
      }
      @submodules
    end

    private def process_type(type : Crystal::Type) : Nil
      return if @visited_types.includes?(type)
      @visited_types << type
      super
    end

    private def process(type : Crystal::Type) : Nil
      type.accept(self) if type.responds_to? :accept

      if type.is_a?(Crystal::Program) || type.is_a?(Crystal::FileModule)
        type.types?.try &.each_value do |inner_type|
          process inner_type
        end
      end

      if type.is_a?(Crystal::GenericType)
        type.generic_types.each_value do |instanced_type|
          process instanced_type
        end
      end

      process type.metaclass if type.metaclass != type
    end

    def visit(node)
      true
    end

    def visit(node : Crystal::Require)
      node.expanded.try &.accept(self)
    end

    private def check_namespace(type)
      current = type
      while current
        return true if current == @target
        break if current.is_a? Crystal::Program
        current = current.namespace
      end
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      if check_namespace(resolved_type = node.resolved_type)
        @submodules << resolved_type unless resolved_type == @target
      end
      true
    end
  end
end
