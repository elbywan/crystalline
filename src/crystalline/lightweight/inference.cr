require "compiler/crystal/syntax"
require "./query"

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
      seed_type_vars_from_summary
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

        process_if(node, apply_cursor_bounds: apply_cursor_bounds)
      when Crystal::Unless
        return unless !apply_cursor_bounds || starts_before_or_at_cursor?(node)

        process_unless(node, apply_cursor_bounds: apply_cursor_bounds)
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
      when Crystal::Or
        infer_or_types(node)
      when Crystal::And
        infer_and_types(node)
      else
        [] of String
      end
    end

    private def infer_or_types(node : Crystal::Or) : Array(String)
      left_types = infer_types(node.left)
      right_types = infer_types(node.right)

      (left_types.reject(&.==("Nil")) + right_types).uniq
    end

    private def infer_and_types(node : Crystal::And) : Array(String)
      left_types = infer_types(node.left)
      right_types = infer_types(node.right)
      nil_types = left_types.select(&.==("Nil"))

      (nil_types + right_types).uniq
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
              return_types.concat(expand_type_names(return_type))
            end
          end
        end
      else
        @query.top_level_methods.each do |method|
          if method.name == node.name && (return_type = method.return_type)
            return_types.concat(expand_type_names(return_type))
          end
        end
      end

      return_types.uniq
    end

    private def expand_type_names(type_name : String) : Array(String)
      normalized = type_name.strip
      normalized = normalized[1...-1] if normalized.starts_with?('(') && normalized.ends_with?(')')
      return [normalized] unless normalized.includes?(" | ")

      normalized.split(" | ").map(&.strip).reject(&.empty?).uniq
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

    private def process_if(node : Crystal::If, *, apply_cursor_bounds : Bool)
      if apply_cursor_bounds
        if contains_cursor?(node.then)
          apply_condition_refinement(node.cond, truthy: true)
          process_node(node.then, apply_cursor_bounds: true)
          return
        elsif contains_cursor?(node.else)
          apply_condition_refinement(node.cond, truthy: false)
          process_node(node.else, apply_cursor_bounds: true)
          return
        end
      end

      process_conditional(node.cond, node.then, node.else, then_truthy: true, else_truthy: false, apply_cursor_bounds: apply_cursor_bounds)
    end

    private def process_unless(node : Crystal::Unless, *, apply_cursor_bounds : Bool)
      if apply_cursor_bounds
        if contains_cursor?(node.then)
          apply_condition_refinement(node.cond, truthy: false)
          process_node(node.then, apply_cursor_bounds: true)
          return
        elsif contains_cursor?(node.else)
          apply_condition_refinement(node.cond, truthy: true)
          process_node(node.else, apply_cursor_bounds: true)
          return
        end
      end

      process_conditional(node.cond, node.then, node.else, then_truthy: false, else_truthy: true, apply_cursor_bounds: apply_cursor_bounds)
    end

    private def process_conditional(cond : Crystal::ASTNode, then_branch : Crystal::ASTNode, else_branch : Crystal::ASTNode, *, then_truthy : Bool, else_truthy : Bool, apply_cursor_bounds : Bool)
      base_state = current_state

      restore_state(base_state)
      apply_condition_refinement(cond, truthy: then_truthy)
      process_node(then_branch, apply_cursor_bounds: apply_cursor_bounds)
      then_state = current_state

      restore_state(base_state)
      apply_condition_refinement(cond, truthy: else_truthy)
      process_node(else_branch, apply_cursor_bounds: apply_cursor_bounds)
      else_state = current_state

      restore_state(base_state)
      @local_types = merge_branch_types(base_state[0], then_state[0], else_state[0])
      @instance_var_types = merge_branch_types(base_state[1], then_state[1], else_state[1])
      @class_var_types = merge_branch_types(base_state[2], then_state[2], else_state[2])
    end

    private def current_state
      {@local_types.dup, @instance_var_types.dup, @class_var_types.dup}
    end

    private def restore_state(state)
      @local_types = state[0].dup
      @instance_var_types = state[1].dup
      @class_var_types = state[2].dup
    end

    private def apply_condition_refinement(node : Crystal::ASTNode, *, truthy : Bool)
      case node
      when Crystal::Not
        apply_condition_refinement(node.exp, truthy: !truthy)
      when Crystal::And
        if truthy
          apply_condition_refinement(node.left, truthy: true)
          apply_condition_refinement(node.right, truthy: true)
        end
      when Crystal::Or
        unless truthy
          apply_condition_refinement(node.left, truthy: false)
          apply_condition_refinement(node.right, truthy: false)
        end
      when Crystal::IsA
        refine_is_a(node, truthy: truthy)
      when Crystal::Call
        if node.name == "nil?" && node.args.empty?
          refine_nil_check(node.obj, truthy: truthy)
        end
      when Crystal::Var, Crystal::InstanceVar, Crystal::ClassVar
        refine_truthiness(node, truthy: truthy)
      end
    end

    private def refine_is_a(node : Crystal::IsA, *, truthy : Bool)
      target_type_names = expand_type_names(node.const.to_s)
      return if target_type_names.empty?

      if truthy
        set_reference_types(node.obj, target_type_names)
      else
        remove_reference_types(node.obj, target_type_names)
      end
    end

    private def refine_nil_check(node : Crystal::ASTNode?, *, truthy : Bool)
      return unless node

      if truthy
        set_reference_types(node, ["Nil"])
      else
        remove_reference_types(node, ["Nil"])
      end
    end

    private def refine_truthiness(node : Crystal::ASTNode, *, truthy : Bool)
      if truthy
        remove_reference_types(node, ["Nil"])
      else
        set_reference_types(node, ["Nil"])
      end
    end

    private def reference_types(node : Crystal::ASTNode) : Array(String)?
      case node
      when Crystal::Var
        node.name == "self" ? self_types[0] : @local_types[node.name]?
      when Crystal::InstanceVar
        @instance_var_types[node.name]?
      when Crystal::ClassVar
        @class_var_types[node.name]?
      when Crystal::Self
        self_types[0]
      end
    end

    private def set_reference_types(node : Crystal::ASTNode, type_names : Array(String))
      normalized = type_names.uniq
      return if normalized.empty?

      case node
      when Crystal::Var
        @local_types[node.name] = normalized unless node.name == "self"
      when Crystal::InstanceVar
        @instance_var_types[node.name] = normalized
      when Crystal::ClassVar
        @class_var_types[node.name] = normalized
      end
    end

    private def remove_reference_types(node : Crystal::ASTNode, excluded_type_names : Array(String))
      current_types = reference_types(node)
      return unless current_types

      remaining_types = current_types.reject { |type_name| excluded_type_names.includes?(type_name) }
      return if remaining_types == current_types

      if remaining_types.empty?
        remaining_types = excluded_type_names.includes?("Nil") ? current_types.reject(&.==("Nil")) : current_types
      end

      set_reference_types(node, remaining_types)
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
        @local_types[arg.name] = expand_type_names(restriction.to_s)
      end
    end

    private def seed_type_vars_from_summary
      return unless type_name = @current_type_name

      if class_method_context?
        @class_var_types = merge_branch_types(@class_var_types, @class_var_types, query_class_var_types(type_name))
      else
        @instance_var_types = merge_branch_types(@instance_var_types, @instance_var_types, query_instance_var_types(type_name))
        @class_var_types = merge_branch_types(@class_var_types, @class_var_types, query_class_var_types(type_name))
      end
    end

    private def query_instance_var_types(type_name : String)
      @query.instance_vars_for(type_name)
    end

    private def query_class_var_types(type_name : String)
      @query.class_vars_for(type_name)
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
