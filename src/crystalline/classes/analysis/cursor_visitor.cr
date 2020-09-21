require "compiler/crystal/**"

module Crystalline
  class CursorVisitor < Crystal::Visitor
    include Crystal::TypedDefProcessor

    getter nodes : Array(Crystal::ASTNode)
    getter context = Hash(String, {Crystal::Type?, Crystal::Location?}).new
    @scoped_vars = Hash(String, {Crystal::Type?, Crystal::Location?}).new
    @previous_vars = Hash(String, {Crystal::Type?, Crystal::Location?}).new
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

      {@nodes, @context}
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

    def visit_any(node : Crystal::Def | Crystal::Assign | Crystal::Block)
      case node
      when Crystal::Assign
        target = node.target
        @scoped_vars[target.to_s] = {node.type?, node.location}
      when Crystal::Def
        node.args.each do |arg|
          @scoped_vars[arg.name] = {arg.type?, arg.location || node.location}
        end
        node.vars.try do |vars|
          vars.each do |name, meta_var|
            @scoped_vars[name] = {meta_var.type?, meta_var.location || node.location}
          end
        end
      when Crystal::Block
        @previous_vars = @scoped_vars.dup
        node.args.each do |arg|
          @scoped_vars[arg.name] = {arg.type?, arg.location || node.location}
        end
        node.vars.try do |vars|
          vars.each do |name, meta_var|
            @scoped_vars[name] = {meta_var.type?, meta_var.location || node.location}
          end
        end
      end
      super
    end

    def end_visit_any(node : Crystal::Def)
      @scoped_vars.clear
    end

    def end_visit_any(node : Crystal::Block)
      @scoped_vars = @previous_vars
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
        @context = @scoped_vars.dup
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
