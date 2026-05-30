require "compiler/crystal/syntax"
require "./lightweight_query"

module Crystalline::Lightweight
  class Inference
    getter local_types = {} of String => Array(String)
    getter current_def : Crystal::Def?

    def self.for(source : String, line : Int32, column : Int32, query : Query) : self?
      new(source, line, column, query).run
    end

    def initialize(@source : String, @line : Int32, @column : Int32, @query : Query)
    end

    def run : self?
      parser = Crystal::Parser.new(@source)
      parser.wants_doc = false
      ast = parser.parse

      @current_def = find_enclosing_def(ast)
      return unless current_def = @current_def

      current_def.args.each do |arg|
        next unless restriction = arg.restriction
        @local_types[arg.name] = [restriction.to_s]
      end

      process_node(current_def.body)
      self
    rescue Crystal::SyntaxException
      nil
    end

    def types_for(name : String) : Array(String)
      @local_types[name]? || [] of String
    end

    private def process_node(node : Crystal::ASTNode)
      case node
      when Crystal::Expressions
        return unless starts_before_or_at_cursor?(node)

        node.expressions.each do |expression|
          break unless starts_before_or_at_cursor?(expression)
          process_node(expression)
        end
      when Crystal::Assign
        return unless before_cursor?(node)

        if target = node.target.as?(Crystal::Var)
          types = infer_types(node.value)
          @local_types[target.name] = types unless types.empty?
        end
      when Crystal::If
        return unless starts_before_or_at_cursor?(node)

        process_node(node.then)
        process_node(node.else)
      when Crystal::Unless
        return unless starts_before_or_at_cursor?(node)

        process_node(node.then)
        process_node(node.else)
      else
        return unless before_cursor?(node)
      end
    end

    private def infer_types(node : Crystal::ASTNode) : Array(String)
      case node
      when Crystal::Var
        types_for(node.name)
      when Crystal::Path
        @query.find_type(node.to_s) ? [node.to_s] : [] of String
      when Crystal::NilLiteral
        ["Nil"]
      when Crystal::BoolLiteral
        ["Bool"]
      when Crystal::CharLiteral
        ["Char"]
      when Crystal::StringLiteral
        ["String"]
      when Crystal::NumberLiteral
        [number_kind_name(node.kind)]
      when Crystal::ArrayLiteral
        ["Array"]
      when Crystal::HashLiteral
        ["Hash"]
      when Crystal::Call
        infer_call_types(node)
      else
        [] of String
      end
    end

    private def infer_call_types(node : Crystal::Call) : Array(String)
      if node.name == "new"
        if object = node.obj
          if path = object.as?(Crystal::Path)
            type_name = path.to_s
            return [type_name] if @query.find_type(type_name)
          end
        end
      end

      return_types = [] of String

      if object = node.obj
        infer_types(object).each do |type_name|
          @query.methods_for(type_name).each do |method|
            if method.name == node.name && (return_type = method.return_type)
              return_types << return_type
            end
          end
        end
      else
        @query.top_level_methods.each do |method|
          if method.name == node.name && (return_type = method.return_type)
            return_types << return_type
          end
        end
      end

      return_types.uniq
    end

    private def number_kind_name(kind : Crystal::NumberKind) : String
      case kind
      when .i8?   then "Int8"
      when .i16?  then "Int16"
      when .i32?  then "Int32"
      when .i64?  then "Int64"
      when .i128? then "Int128"
      when .u8?   then "UInt8"
      when .u16?  then "UInt16"
      when .u32?  then "UInt32"
      when .u64?  then "UInt64"
      when .u128? then "UInt128"
      when .f32?  then "Float32"
      when .f64?  then "Float64"
      else             "Int32"
      end
    end

    private def find_enclosing_def(node : Crystal::ASTNode) : Crystal::Def?
      best = nil.as(Crystal::Def?)
      walker = uninitialized Proc(Crystal::ASTNode, Nil)
      walker = ->(current : Crystal::ASTNode) do
        if current.is_a?(Crystal::Def) && contains_cursor?(current)
          best = current
        end

        case current
        when Crystal::Expressions
          current.expressions.each { |expression| walker.call(expression) if contains_cursor?(expression) || starts_before_or_at_cursor?(expression) }
        when Crystal::Def
          current.body.try { |body| walker.call(body) if contains_cursor?(body) || starts_before_or_at_cursor?(body) }
        when Crystal::If
          walker.call(current.then) if contains_cursor?(current.then) || starts_before_or_at_cursor?(current.then)
          walker.call(current.else) if contains_cursor?(current.else) || starts_before_or_at_cursor?(current.else)
        when Crystal::Unless
          walker.call(current.then) if contains_cursor?(current.then) || starts_before_or_at_cursor?(current.then)
          walker.call(current.else) if contains_cursor?(current.else) || starts_before_or_at_cursor?(current.else)
        end
      end

      walker.call(node)
      best
    end

    private def contains_cursor?(node : Crystal::ASTNode)
      start_loc = node.location
      end_loc = node.end_location
      return false unless start_loc && end_loc

      compare_position(start_loc.line_number, start_loc.column_number, @line, @column) <= 0 &&
        compare_position(end_loc.line_number, end_loc.column_number, @line, @column) >= 0
    end

    private def before_cursor?(node : Crystal::ASTNode)
      end_loc = node.end_location
      return false unless end_loc

      compare_position(end_loc.line_number, end_loc.column_number, @line, @column) < 0
    end

    private def starts_before_or_at_cursor?(node : Crystal::ASTNode)
      start_loc = node.location
      return false unless start_loc

      compare_position(start_loc.line_number, start_loc.column_number, @line, @column) <= 0
    end

    private def compare_position(line_a : Int32, col_a : Int32, line_b : Int32, col_b : Int32)
      return line_a <=> line_b unless line_a == line_b
      col_a <=> col_b
    end
  end
end
