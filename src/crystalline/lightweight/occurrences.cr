require "lsp/server"
require "compiler/crystal/syntax"
require "../source_mask"
require "../utils"
require "./resolver"

# An argument of a def, block or proc literal: block arguments are `Var`
# nodes while def arguments are `Arg` nodes, this record normalizes both.
private record ScopeArg,
  name : String,
  location : Crystal::Location?,
  default_value : Crystal::ASTNode? = nil

# The arguments and body of a def, block or proc literal (empty for other
# nodes). Visible in this file only.
private def scope_parts(node : Crystal::ASTNode) : {Array(ScopeArg), Crystal::ASTNode?}
  case node
  when Crystal::Def
    {node.args.map { |arg| ScopeArg.new(arg.name, arg.location, arg.default_value) }, node.body}
  when Crystal::Block
    {node.args.map { |arg| ScopeArg.new(arg.name, arg.location) }, node.body}
  when Crystal::ProcLiteral
    {node.def.args.map { |arg| ScopeArg.new(arg.name, arg.location, arg.default_value) }, node.def.body}
  else
    {[] of ScopeArg, nil}
  end
end

module Crystalline::Lightweight
  # Locates a local variable, parameter or block argument at a position and
  # collects all of its occurrences.
  #
  # These are the only symbols the lightweight engine resolves exactly: the
  # parser records a location for every variable occurrence (`Var#location`,
  # `Arg#location`) and the language scopes them to their enclosing def, block
  # or proc literal. Methods, types and instance variables have no reference
  # index, so their occurrences cannot be computed without a full compilation.
  class Occurrences
    record Occurrence, range : LSP::Range, write : Bool

    getter occurrences : Array(Occurrence)

    def self.at(source : String, line_number : Int32, column_number : Int32) : self?
      lines = source.lines(chomp: false)
      line = lines[line_number]?
      return unless line

      span = Resolver.token_span(line, column_number)
      return unless span

      start_index, end_index = span
      return if SourceMask.new(source).comment_or_string?(line_number, start_index)

      name = line[start_index, end_index - start_index]?
      return unless name && Resolver.local_name?(name)

      ast = Crystal::Parser.new(source).parse
      scope = ScopeFinder.new(line_number, start_index, name).find(ast)
      return unless scope

      occurrences = Collector.new(name, lines).collect(scope)

      # The cursor must sit on a collected occurrence: a method call sharing
      # the name of a local variable in the same scope is not an occurrence.
      cursor_column = PositionUtils.char_to_utf16_index(line, start_index)
      return unless occurrences.any? { |occurrence|
                      occurrence.range.start.line == line_number && occurrence.range.start.character == cursor_column
                    }

      new(occurrences)
    rescue Crystal::SyntaxException
      # A buffer that does not parse has no scopes to resolve.
      nil
    end

    private def initialize(@occurrences : Array(Occurrence))
    end

    # Finds the innermost def, block or proc literal the cursor is in, and
    # reports whether the cursor sits inside a macro body: macro bodies are
    # raw text, their variables are not scoped by the surrounding syntax.
    private class ScopeFinder < Crystal::Visitor
      getter? in_macro = false

      def initialize(@line_number : Int32, @column : Int32, @name : String)
        @scopes = [] of Crystal::ASTNode
      end

      # `@scopes` is ordered from the outermost scope to the innermost one.
      def find(node : Crystal::ASTNode) : Crystal::ASTNode?
        node.accept(self)
        return if in_macro?

        # An argument shadowing the name wins from the innermost scope.
        if shadowing = @scopes.reverse_each.find { |scope| argument?(scope) }
          return shadowing
        end

        # Otherwise the variable belongs to the outermost scope assigning it:
        # an assignment inside a block or a proc only creates a new variable
        # when the name is not declared around it.
        @scopes.find { |scope| assigns?(scope) } || @scopes.last? || node
      end

      def visit(node : Crystal::Def | Crystal::Block | Crystal::ProcLiteral)
        @scopes << node if contains?(node)
        true
      end

      def visit(node : Crystal::Macro)
        @in_macro = true if contains?(node)
        false
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      # Containment on both axes: scopes sharing a line (one-line defs, chained
      # one-line blocks) must not be conflated.
      private def contains?(node : Crystal::ASTNode) : Bool
        location = node.location
        end_location = node.end_location
        return false unless location && end_location

        start_line = location.line_number - 1
        end_line = end_location.line_number - 1
        return false if @line_number < start_line || @line_number > end_line
        return false if @line_number == start_line && @column < location.column_number - 1
        return false if @line_number == end_line && @column > end_location.column_number - 1

        true
      end

      private def argument?(scope : Crystal::ASTNode) : Bool
        args, _body = scope_parts(scope)
        args.any? { |arg| arg.name == @name }
      end

      # True when the scope's own body assigns the name. Nested scopes are not
      # entered: whether they assign it is answered for them.
      private def assigns?(scope : Crystal::ASTNode) : Bool
        _args, body = scope_parts(scope)
        DeclarationFinder.new(@name).find(body)
      end
    end

    # Finds an assignment to a name inside a scope body, without entering
    # nested scopes.
    private class DeclarationFinder < Crystal::Visitor
      def initialize(@name : String)
        @found = false
      end

      def find(body : Crystal::ASTNode?) : Bool
        body.try &.accept(self)
        @found
      end

      def visit(node : Crystal::Assign | Crystal::OpAssign)
        target = node.target.as?(Crystal::Var)
        @found = true if target && target.name == @name
        !@found
      end

      def visit(node : Crystal::MultiAssign)
        @found = true if node.targets.any? { |target| (var = target.as?(Crystal::Var)) && var.name == @name }
        !@found
      end

      def visit(node : Crystal::TypeDeclaration)
        var = node.var.as?(Crystal::Var)
        @found = true if var && var.name == @name
        !@found
      end

      def visit(node : Crystal::Def | Crystal::Block | Crystal::ProcLiteral | Crystal::Macro)
        false
      end

      def visit(node : Crystal::ASTNode)
        !@found
      end
    end

    # Collects the occurrences of a name within a scope. Blocks and procs that
    # declare the name shadow it and are skipped, the others are entered: a
    # closure reads and writes the enclosing variable.
    private class Collector < Crystal::Visitor
      getter occurrences = [] of Occurrence

      def initialize(@name : String, @lines : Array(String))
      end

      def collect(scope : Crystal::ASTNode) : Array(Occurrence)
        args, body = scope_parts(scope)
        args.each do |arg|
          record(arg.location, write: true, name: arg.name)
          arg.default_value.try &.accept(self)
        end

        case scope
        when Crystal::Def, Crystal::Block, Crystal::ProcLiteral
          body.try &.accept(self)
        else
          # No enclosing def/block/proc: top level variables.
          scope.accept(self)
        end

        occurrences
      end

      def visit(node : Crystal::Assign | Crystal::OpAssign)
        if target = node.target.as?(Crystal::Var)
          record(target.location, write: true, name: target.name)
        else
          # `obj.attribute = value`: the target may read the renamed variable.
          node.target.accept(self)
        end
        node.value.accept(self)
        false
      end

      def visit(node : Crystal::MultiAssign)
        node.targets.each do |target|
          if var = target.as?(Crystal::Var)
            record(var.location, write: true, name: var.name)
          else
            target.accept(self)
          end
        end
        node.values.each &.accept(self)
        false
      end

      def visit(node : Crystal::TypeDeclaration)
        if var = node.var.as?(Crystal::Var)
          record(var.location, write: true, name: var.name)
        else
          node.var.accept(self)
        end
        node.value.try &.accept(self)
        false
      end

      def visit(node : Crystal::Var)
        record(node.location, write: false, name: node.name)
        true
      end

      # Only arguments shadow: assigning a name declared outside writes the
      # enclosing variable. The body is visited explicitly because a proc
      # literal wraps its body in a synthetic def, which the overload below
      # would skip.
      def visit(node : Crystal::Block | Crystal::ProcLiteral)
        args, body = scope_parts(node)
        return false if args.any? { |arg| arg.name == @name }

        body.try &.accept(self)
        false
      end

      # A nested def cannot read this scope's variables, a macro body is raw
      # text.
      def visit(node : Crystal::Def | Crystal::Macro)
        false
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def record(location : Crystal::Location?, *, write : Bool, name : String?) : Nil
        return unless name && name == @name
        return unless location

        occurrences << Occurrence.new(
          range: Utils.lsp_range(@lines, location, @name.size),
          write: write,
        )
      end
    end
  end
end
