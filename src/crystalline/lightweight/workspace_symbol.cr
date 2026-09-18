require "lsp/server"
require "uri"
require "compiler/crystal/syntax"
require "../utils"
require "./index"

module Crystalline::Lightweight
  # Lists the symbols of an index matching a query: a case insensitive
  # substring match, symbols whose name starts with the query first.
  #
  # Only symbols defined in the project sources are listed: standard library
  # and dependency (`lib/`) symbols would otherwise drown the results.
  class WorkspaceSymbol
    def self.symbols(index : Index, root_path : String, query : String) : Array(LSP::SymbolInformation)
      new(index, root_path, query).symbols
    end

    @lines = {} of String => Array(String)?

    def initialize(@index : Index, @root_path : String, @query : String)
      # Anchored with a separator: `/proj-app` must not match the root `/proj`.
      @root_prefix = root_path.chomp('/') + "/"
      @dependency_path = File.join(root_path, "lib") + "/"
      @needle = query.downcase
    end

    def symbols : Array(LSP::SymbolInformation)
      ranked = [] of {Int32, String, LSP::SymbolInformation}

      @index.types.each_value do |type_info|
        name = type_info.name.split("::").last
        if rank = rank(name)
          if symbol = type_symbol(type_info, name)
            ranked << {rank, name, symbol}
          end
        end

        type_info.methods.each do |method|
          next unless rank = rank(method.name)
          next unless symbol = method_symbol(type_info, method)

          ranked << {rank, method.name, symbol}
        end
      end

      @index.top_level_methods.each do |method|
        next unless rank = rank(method.name)
        next unless symbol = method_symbol(nil, method, owner_label: nil, kind: LSP::SymbolKind::Function)

        ranked << {rank, method.name, symbol}
      end

      ranked.sort_by! { |(rank, name, _symbol)| {rank, name} }
      ranked.map { |(_, _, symbol)| symbol }
    end

    # 0 when the name starts with the query, 1 when it contains it, nil
    # otherwise (and when the query is empty every name matches).
    private def rank(name : String) : Int32?
      downcased = name.downcase
      return 0 if downcased.starts_with?(@needle)
      return 1 if downcased.includes?(@needle)

      nil
    end

    private def type_symbol(type_info : TypeInfo, name : String) : LSP::SymbolInformation?
      location = type_info.name_location || type_info.location
      return unless filename = symbol_filename(location)

      range = Utils.lsp_range(file_lines(filename), location.not_nil!, name.size)
      LSP::SymbolInformation.new(
        name: name,
        kind: type_kind(type_info.kind),
        deprecated: nil,
        location: LSP::Location.new(uri: file_uri(filename), range: range),
        container_name: container_name(type_info.name),
      )
    end

    private def method_symbol(owner : TypeInfo?, method : MethodInfo, *, owner_label = owner.try(&.name), kind : LSP::SymbolKind? = nil) : LSP::SymbolInformation?
      location = method.name_location || method.location
      return unless filename = symbol_filename(location)

      name = method.name
      size = method.name_size > 0 ? method.name_size : name.size
      range = Utils.lsp_range(file_lines(filename), location.not_nil!, size)
      LSP::SymbolInformation.new(
        name: name,
        kind: kind || (name == "initialize" ? LSP::SymbolKind::Constructor : LSP::SymbolKind::Method),
        deprecated: nil,
        location: LSP::Location.new(uri: file_uri(filename), range: range),
        container_name: owner_label,
      )
    end

    # The namespace of a type name: `Crystalline::Utils` -> `Crystalline`.
    private def container_name(type_name : String) : String?
      return if type_name.starts_with?("::")

      parts = type_name.split("::")
      return if parts.size < 2

      parts[0...-1].join("::")
    end

    # The file of the symbol, when it belongs to the project sources.
    private def symbol_filename(location : Crystal::Location?) : String?
      return unless location
      return unless filename = location.original_filename

      filename if filename.starts_with?(@root_prefix) && !filename.starts_with?(@dependency_path)
    end

    private def file_uri(filename : String) : String
      "file://#{URI.encode_path(filename)}"
    end

    private def file_lines(filename : String) : Array(String)
      if @lines.has_key?(filename)
        return @lines[filename] || [] of String
      end

      lines = File.exists?(filename) ? File.read(filename).lines(chomp: false) : nil
      @lines[filename] = lines
      lines || [] of String
    end

    private def type_kind(kind : TypeKind) : LSP::SymbolKind
      case kind
      in TypeKind::Class      then LSP::SymbolKind::Class
      in TypeKind::Module     then LSP::SymbolKind::Module
      in TypeKind::Struct     then LSP::SymbolKind::Struct
      in TypeKind::Enum       then LSP::SymbolKind::Enum
      in TypeKind::Annotation then LSP::SymbolKind::Interface
      in TypeKind::Alias      then LSP::SymbolKind::TypeParameter
      in TypeKind::Lib        then LSP::SymbolKind::Interface
      in TypeKind::Constant   then LSP::SymbolKind::Constant
      in TypeKind::Unknown    then LSP::SymbolKind::Object
      end
    end
  end
end
