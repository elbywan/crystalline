module Crystalline::Utils
  def self.map_completion_kind(kind, *, default = LSP::CompletionItemKind::Variable)
    case kind
    when Crystal::FileModule
      LSP::CompletionItemKind::File
    when Crystal::Const
      LSP::CompletionItemKind::Constant
    when Crystal::ClassType
      LSP::CompletionItemKind::Class
    when Crystal::EnumType
      LSP::CompletionItemKind::Enum
    when Crystal::LibType
      LSP::CompletionItemKind::Interface
    when Crystal::ModuleType
      LSP::CompletionItemKind::Module
    else
      default
    end
  end

  def self.locations_from_path(path : Crystal::Path, nodes : Array(Crystal::ASTNode)) : Array({Crystal::Location, Crystal::Location})?
    target = self.resolve_path(path, nodes)
    target.as?(Crystal::Const | Crystal::Type).try &.locations.try &.map do |location|
      end_location = Crystal::Location.new(
        location.filename,
        line_number: location.line_number + 1,
        column_number: 0
      )
      {location, end_location}
    end
  end

  def self.locations_from_union(union : Crystal::Union, nodes : Array(Crystal::ASTNode), *, locations = [] of {Crystal::Location, Crystal::Location}) : Array({Crystal::Location, Crystal::Location})
    union.types.each { |type|
      if type.is_a? Crystal::Path
        locations_from_path(type, nodes).try { |locs|
          locations.concat locs
        }
      elsif type.is_a? Crystal::Union
        self.locations_from_union(type, nodes, locations: locations)
      elsif location = type.location
        end_location = type.end_location || location
        locations << {location, end_location}
      end
    }
    locations
  end

  def self.resolve_path(path : Crystal::Path, ast_nodes : Array(Crystal::ASTNode))
    resolved_path = path.type? || path.target_const || path.target_type || ast_nodes[..-2]?.try &.reverse_each.reduce(nil) do |_, elt|
      if elt.responds_to? :resolved_type
        typ = elt.resolved_type
      end

      typ ||= elt.type?

      if p = (typ.try &.lookup_path(path))
        break p
      end
    end

    if resolved_path.is_a? Crystal::Type
      resolved_path.instance_type
    else
      resolved_path
    end
  end

  def self.lsp_range_from_node(node : Crystal::ASTNode)
    start_location = node.location
    end_location = node.end_location || start_location
    LSP::Range.new(
      start: LSP::Position.new(
        line:      start_location.try(&.line_number.- 1) || 0,
        character: start_location.try(&.column_number.- 1) || 0,
      ),
      end: LSP::Position.new(
        line:      end_location.try(&.line_number.- 1) || 0,
        character: end_location.try(&.column_number.- 1) || 0,
      ),
    )
  end

  # Format a method definition or macro.
  def self.format_def(d : Crystal::Def | Crystal::Macro, *, short = false)
    String.build { |str|
      unless short
        str << d.visibility.to_s.downcase
        str << ' '
      end

      str << d.name
      str << ' '

      if d.args.size > 0 || d.block_arg || d.double_splat
        str << '('
        printed_arg = false
        d.args.each_with_index do |arg, i|
          str << ", " if printed_arg
          str << '*' if d.splat_index == i
          str << arg.to_s
          printed_arg = true
        end
        if double_splat = d.double_splat
          str << ", " if printed_arg
          str << "**"
          str << double_splat
          printed_arg = true
        end
        if d.block_arg
          str << ", " if printed_arg
          str << '&'
          printed_arg = true
        end
        str << ')'
      end
      if d.responds_to?(:return_type) && (return_type = d.return_type)
        str << " : #{return_type}"
      end

      if d.responds_to?(:free_vars) && (free_vars = d.free_vars)
        str << " forall "
        free_vars.join(str, ", ")
      end
    }
  rescue e
    # LSP::Log.error(exception: e) { e.to_s }
    d.to_s
  end
end
