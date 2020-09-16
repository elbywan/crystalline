require "compiler/crystal/**"

module Crystalline
  class CursorVisitor < Crystal::Visitor
    include Crystal::TypedDefProcessor

    getter nodes : Array(Crystal::ASTNode)
    @top_level = false

    def initialize(@target_location : Crystal::Location)
      @nodes = [] of Crystal::ASTNode
      @visited_types = Set(Crystal::Type).new
    end

    def process(result : Crystal::Compiler::Result)
      process_result result

      if @nodes.empty?
        @top_level = true
        result.node.accept(self)
      end

      @nodes
    end

    private def process_type(type : Crystal::Type) : Nil
      return if @visited_types.includes?(type)
      @visited_types << type
      super
    end

    private def nearest_end_location(node)
      return node.end_location if node.end_location

      @nodes.reverse.find { |elt|
        elt.responds_to?(:end_location) && elt.end_location
      }.try &.end_location
    end

    def visit(node)
      if node_location = node.location
        node_end_location = nearest_end_location(node)

        if @top_level
          node_end_location ||= Crystal::Location.new(
            node_location.filename,
            line_number: node_location.line_number + 1,
            column_number: 0
          )
        end

        contains_node = @target_location.between?(node_location, node_end_location) if node_end_location
      end

      if contains_node
        @nodes << node
        true
      elsif @top_level && @nodes.empty?
        if node.is_a? Crystal::Require
          node.expanded.try &.accept(self)
        else
          true
        end
      else
        contains_target(node)
      end
    end
  end
end
