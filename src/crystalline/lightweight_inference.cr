require "compiler/crystal/syntax"
require "./lightweight_query"

module Crystalline::Lightweight
  class Inference
    getter local_types = {} of String => Array(String)
    getter instance_var_types = {} of String => Array(String)
    getter class_var_types = {} of String => Array(String)
    getter current_def : Crystal::Def?
    getter current_type_name : String?
    getter? class_method_context = false
    @current_type_body : Crystal::ASTNode? = nil

    def self.for(source : String, line : Int32, column : Int32, query : Query) : self?
      new(source, line, column, query).run
    end

    def initialize(@source : String, @line : Int32, @column : Int32, @query : Query)
    end

    def run : self?
      parser = Crystal::Parser.new(@source)
      parser.wants_doc = false
      ast = parser.parse

      return unless locate_context(ast)
      return unless current_def = @current_def

      seed_arg_types(current_def)
      process_initialize_defs unless class_method_context? || current_def.name == "initialize"
      process_node(current_def.body)
      self
    rescue Crystal::SyntaxException
      nil
    end

    def types_for(name : String) : Array(String)
      @local_types[name]? || [] of String
    end

    def types_for_instance_var(name : String) : Array(String)
      @instance_var_types[name]? || [] of String
    end

    def types_for_class_var(name : String) : Array(String)
      @class_var_types[name]? || [] of String
    end

    def self_types : {Array(String), Bool}
      if type_name = @current_type_name
        {[type_name], class_method_context?}
      else
        {[] of String, false}
      end
    end

    private def process_node(node : Crystal::ASTNode, *, apply_cursor_bounds = true)
      case node
      when Crystal::Expressions
        return unless !apply_cursor_bounds || starts_before_or_at_cursor?(node)

        node.expressions.each do |expression|
          break if apply_cursor_bounds && !starts_before_or_at_cursor?(expression)
          process_node(expression, apply_cursor_bounds: apply_cursor_bounds)
        end
      when Crystal::Assign
        return unless !apply_cursor_bounds || before_cursor?(node)

        types = infer_types(node.value)
        return if types.empty?

        case target = node.target
        when Crystal::Var
          @local_types[target.name] = types
        when Crystal::InstanceVar
          @instance_var_types[target.name] = types
        when Crystal::ClassVar
          @class_var_types[target.name] = types
        end
      when Crystal::If
        return unless !apply_cursor_bounds || starts_before_or_at_cursor?(node)

        process_conditional(node.then, node.else, apply_cursor_bounds: apply_cursor_bounds)
      when Crystal::Unless
        return unless !apply_cursor_bounds || starts_before_or_at_cursor?(node)

        process_conditional(node.then, node.else, apply_cursor_bounds: apply_cursor_bounds)
      else
        return unless !apply_cursor_bounds || before_cursor?(node)
      end
    end

    private def infer_types(node : Crystal::ASTNode) : Array(String)
      case node
      when Crystal::Var
        node.name == "self" ? self_types[0] : types_for(node.name)
      when Crystal::InstanceVar
        types_for_instance_var(node.name)
      when Crystal::ClassVar
        types_for_class_var(node.name)
      when Crystal::Self
        self_types[0]
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

    private def locate_context(node : Crystal::ASTNode) : Bool
      found = false
      walker = uninitialized Proc(Crystal::ASTNode, String?, Crystal::ASTNode?, Nil)
      walker = ->(current : Crystal::ASTNode, type_name : String?, type_body : Crystal::ASTNode?) do
        case current
        when Crystal::ClassDef
          qualified_name = qualify_type_name(current.name.to_s, type_name)
          walker.call(current.body, qualified_name, current.body) if contains_cursor?(current.body) || starts_before_or_at_cursor?(current.body)
        when Crystal::ModuleDef
          qualified_name = qualify_type_name(current.name.to_s, type_name)
          walker.call(current.body, qualified_name, current.body) if contains_cursor?(current.body) || starts_before_or_at_cursor?(current.body)
        when Crystal::EnumDef
          qualified_name = qualify_type_name(current.name.to_s, type_name)
          current.members.each do |member|
            walker.call(member, qualified_name, type_body) if contains_cursor?(member) || starts_before_or_at_cursor?(member)
          end
        when Crystal::Expressions
          current.expressions.each do |expression|
            walker.call(expression, type_name, type_body) if contains_cursor?(expression) || starts_before_or_at_cursor?(expression)
          end
        when Crystal::Def
          if contains_cursor?(current)
            @current_def = current
            @current_type_name = type_name
            @class_method_context = !current.receiver.nil?
            @current_type_body = type_body
            found = true
          end
        when Crystal::If
          walker.call(current.then, type_name, type_body) if contains_cursor?(current.then) || starts_before_or_at_cursor?(current.then)
          walker.call(current.else, type_name, type_body) if contains_cursor?(current.else) || starts_before_or_at_cursor?(current.else)
        when Crystal::Unless
          walker.call(current.then, type_name, type_body) if contains_cursor?(current.then) || starts_before_or_at_cursor?(current.then)
          walker.call(current.else, type_name, type_body) if contains_cursor?(current.else) || starts_before_or_at_cursor?(current.else)
        end
      end

      walker.call(node, nil, nil)
      found
    end

    private def process_conditional(then_branch : Crystal::ASTNode, else_branch : Crystal::ASTNode, *, apply_cursor_bounds : Bool)
      base_local_types = @local_types.dup
      base_instance_var_types = @instance_var_types.dup
      base_class_var_types = @class_var_types.dup

      process_node(then_branch, apply_cursor_bounds: apply_cursor_bounds)
      then_local_types = @local_types.dup
      then_instance_var_types = @instance_var_types.dup
      then_class_var_types = @class_var_types.dup

      @local_types = base_local_types.dup
      @instance_var_types = base_instance_var_types.dup
      @class_var_types = base_class_var_types.dup

      process_node(else_branch, apply_cursor_bounds: apply_cursor_bounds)
      else_local_types = @local_types.dup
      else_instance_var_types = @instance_var_types.dup
      else_class_var_types = @class_var_types.dup

      @local_types = merge_branch_types(base_local_types, then_local_types, else_local_types)
      @instance_var_types = merge_branch_types(base_instance_var_types, then_instance_var_types, else_instance_var_types)
      @class_var_types = merge_branch_types(base_class_var_types, then_class_var_types, else_class_var_types)
    end

    private def merge_branch_types(base : Hash(String, Array(String)), left : Hash(String, Array(String)), right : Hash(String, Array(String)))
      merged = {} of String => Array(String)

      (base.keys | left.keys | right.keys).each do |name|
        candidates = [] of String
        candidates.concat(left[name]? || base[name]? || [] of String)
        candidates.concat(right[name]? || base[name]? || [] of String)
        merged[name] = candidates.uniq unless candidates.empty?
      end

      merged
    end

    private def seed_arg_types(definition : Crystal::Def)
      definition.args.each do |arg|
        next unless restriction = arg.restriction
        @local_types[arg.name] = [restriction.to_s]
      end
    end

    private def process_initialize_defs
      type_body = @current_type_body
      return unless type_body

      each_direct_def(type_body) do |definition|
        next unless definition.name == "initialize"
        next if definition.receiver

        saved_local_types = @local_types.dup
        begin
          @local_types.clear
          seed_arg_types(definition)
          process_node(definition.body, apply_cursor_bounds: false)
        ensure
          @local_types = saved_local_types
        end
      end
    end

    private def each_direct_def(node : Crystal::ASTNode, & : Crystal::Def ->)
      case node
      when Crystal::Expressions
        node.expressions.each do |expression|
          yield expression if expression.is_a?(Crystal::Def)
        end
      when Crystal::Def
        yield node
      end
    end

    private def qualify_type_name(name : String, parent_type_name : String?) : String
      return name if name.includes?("::") || parent_type_name.nil?
      "#{parent_type_name}::#{name}"
    end

    private def contains_cursor?(node : Crystal::ASTNode)
      start_loc = node.location
      end_loc = node.end_location || start_loc
      return false unless start_loc && end_loc

      compare_position(start_loc.line_number, start_loc.column_number, @line, @column) <= 0 &&
        compare_position(end_loc.line_number, end_loc.column_number, @line, @column) >= 0
    end

    private def before_cursor?(node : Crystal::ASTNode)
      end_loc = node.end_location || node.location
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
