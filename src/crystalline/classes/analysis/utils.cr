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
end
