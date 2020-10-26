module Crystalline
  class DocumentSymbolsVisitor < Crystal::Visitor
    getter symbols = Array(LSP::DocumentSymbol).new
    @parent_symbol : LSP::DocumentSymbol? = nil
    @parent_macro_call : Crystal::Call? = nil

    private def create_symbol_from_node(node : Crystal::ASTNode, kind : LSP::SymbolKind, detail : String? = nil)
      range = Utils.lsp_range_from_node(@parent_macro_call || node)
      name = node.responds_to?(:name) ? node.name.to_s : node.to_s
      LSP::DocumentSymbol.new(
        name:            name,
        detail:          detail,
        kind:            kind,
        range:           range,
        selection_range: range,
        children:        [] of LSP::DocumentSymbol,
      )
    end

    private def append_symbol(symbol : LSP::DocumentSymbol)
      (@parent_symbol.try(&.children) || @symbols) << symbol
    end

    private def with_parent(symbol : LSP::DocumentSymbol)
      append_symbol(symbol)
      old_parent = @parent_symbol
      @parent_symbol = symbol
      yield
      @parent_symbol = old_parent
    end

    def visit(node)
      # LSP::Log.info { "#{node.class}: #{node}" }
      true
    end

    def visit(node : Crystal::ClassDef)
      symbol = create_symbol_from_node(node, :class)
      with_parent(symbol) do
        node.body.accept self
      end
      false
    end

    def visit(node : Crystal::ModuleDef)
      symbol = create_symbol_from_node(node, :module)
      with_parent(symbol) do
        node.body.accept self
      end
      false
    end

    def visit(node : Crystal::AnnotationDef)
      symbol = create_symbol_from_node(node, :property)
      append_symbol(symbol)
      false
    end

    def visit(node : Crystal::EnumDef)
      symbol = create_symbol_from_node(node, :enum)
      with_parent(symbol) do
        node.members.each &.accept self
      end
      false
    end

    def visit(node : Crystal::LibDef)
      symbol = create_symbol_from_node(node, :module)
      with_parent(symbol) do
        node.body.accept self
      end
      false
    end

    def visit(node : Crystal::Alias)
      symbol = create_symbol_from_node(node, :type_parameter)
      append_symbol(symbol)
      false
    end

    def visit(node : Crystal::Def)
      symbol = create_symbol_from_node(node, :function, detail: Utils.format_def(node))
      append_symbol(symbol)
      false
    end

    def visit(node : Crystal::Macro)
      symbol = create_symbol_from_node(node, :method, detail: Utils.format_def(node))
      append_symbol(symbol)
      false
    end

    def visit(node : Crystal::Arg)
      if (@parent_symbol.try &.kind.enum?)
        symbol = create_symbol_from_node(node, :enum_member)
        append_symbol(symbol)
      end
      false
    end

    def visit(node : Crystal::Call)
      if (expanded = node.expanded)
        @parent_macro_call = node
        expanded.accept(self)
        @parent_macro_call = nil
      end
      false
    end

    def visit(node : Crystal::Require)
      # symbol = create_symbol_from_node(node, :package)
      # append_symbol(symbol)
      false
    end

    def visit(node : Crystal::InstanceVar)
      symbol = create_symbol_from_node(node, :field)
      append_symbol(symbol)
      false
    end

    def visit(node : Crystal::ClassVar)
      symbol = create_symbol_from_node(node, :field)
      append_symbol(symbol)
      false
    end

    def end_visit(node)
    end
  end
end
