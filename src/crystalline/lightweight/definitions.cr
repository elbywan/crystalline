require "lsp/server"
require "compiler/crystal/syntax"
require "./query"
require "./resolver"

module Crystalline::Lightweight
  class Definitions
    record TypeDefInfo, name : String, location : Crystal::Location?, name_location : Crystal::Location?, name_size : Int32
    record DefInfo, owner : String?, definition : Crystal::Def, class_method : Bool

    def self.definitions(source : String, file_uri : URI, line_number : Int32, column_number : Int32, query : Query?) : Array(LSP::Location)?
      new(source, file_uri, line_number, column_number, query).definitions
    end

    def self.diagnose(source : String, file_uri : URI, line_number : Int32, column_number : Int32, query : Query?) : String
      new(source, file_uri, line_number, column_number, query).diagnose
    end

    def initialize(@source : String, @file_uri : URI, @line_number : Int32, @column_number : Int32, @query : Query?)
    end

    def definitions : Array(LSP::Location)?
      definitions_or_reason[0]
    rescue Crystal::SyntaxException
      nil
    end

    def diagnose : String
      definitions_or_reason[1]
    rescue Crystal::SyntaxException
      "syntax error while parsing definitions"
    end

    private def definitions_or_reason : {Array(LSP::Location)?, String}
      line = @source.lines(chomp: false)[@line_number]?
      return {nil, "no line at cursor"} unless line

      span = token_span(line)
      return {nil, "no token at cursor"} unless span

      start_index, end_index = span
      token = line[start_index, end_index - start_index]?
      return {nil, "empty token at cursor"} unless token && !token.empty?

      if start_index > 0 && line[start_index - 1] == '.'
        receiver = Resolver.receiver_from_prefix(line[0, start_index - 1])
        return {nil, "missing query for method definitions"} unless query = @query
        definitions = locations_for_method(receiver, token, start_index - 1, query)
        return {definitions, definitions ? "resolved" : "no lightweight method definitions for receiver '#{receiver}' and method '#{token}'"}
      end

      if Resolver.type_name?(token)
        definitions = locations_for_type(token)
        return {definitions, definitions ? "resolved" : "no lightweight type definition for '#{token}'"}
      end

      if Resolver.local_name?(token)
        definitions = locations_for_top_level_method(token)
        return {definitions, definitions ? "resolved" : "no lightweight top-level method definition for '#{token}'"}
      end

      {nil, "unsupported definitions token '#{token}'"}
    end

    private def locations_for_method(receiver : String, method_name : String, analysis_column : Int32, query : Query) : Array(LSP::Location)?
      type_names, class_method = Resolver.receiver_types(@source, @line_number, analysis_column, receiver, query)
      return if type_names.empty?

      matches = def_infos.select do |info|
        type_names.includes?(info.owner) && info.class_method == class_method && info.definition.name == method_name
      end
      build_locations(matches.map(&.definition))
    end

    private def locations_for_type(type_name : String) : Array(LSP::Location)?
      matches = type_defs.select do |info|
        info.name == type_name || info.name.split("::").last == type_name
      end
      build_type_locations(matches)
    end

    private def locations_for_top_level_method(method_name : String) : Array(LSP::Location)?
      matches = def_infos.select do |info|
        info.owner.nil? && info.definition.name == method_name
      end
      build_locations(matches.map(&.definition))
    end

    private def build_locations(definitions : Array(Crystal::Def)) : Array(LSP::Location)?
      locations = definitions.compact_map do |definition|
        name_location = definition.name_location || definition.location
        next unless name_location

        end_location = Crystal::Location.new(
          name_location.filename,
          name_location.line_number,
          name_location.column_number + definition.name.size - 1,
        )

        lsp_location(name_location, end_location)
      end

      locations.empty? ? nil : locations
    end

    private def build_type_locations(type_infos : Array(TypeDefInfo)) : Array(LSP::Location)?
      locations = type_infos.compact_map do |info|
        start_location = info.name_location || info.location
        next unless start_location

        end_location = Crystal::Location.new(
          start_location.filename,
          start_location.line_number,
          start_location.column_number + info.name_size - 1,
        )

        lsp_location(start_location, end_location)
      end

      locations.empty? ? nil : locations
    end

    private def lsp_location(start_location : Crystal::Location, end_location : Crystal::Location) : LSP::Location
      LSP::Location.new(
        uri: "file://#{start_location.original_filename}",
        range: LSP::Range.new(
          start: LSP::Position.new(line: start_location.line_number - 1, character: start_location.column_number - 1),
          end: LSP::Position.new(line: end_location.line_number - 1, character: end_location.column_number),
        ),
      )
    end

    private def def_infos : Array(DefInfo)
      infos = [] of DefInfo
      visit_defs(parsed_ast, infos)
      infos
    end

    private def visit_defs(node : Crystal::ASTNode, infos : Array(DefInfo), namespace : String? = nil)
      case node
      when Crystal::Expressions
        node.expressions.each { |expression| visit_defs(expression, infos, namespace) }
      when Crystal::ClassDef
        visit_defs(node.body, infos, qualify_type_name(node.name.to_s, namespace))
      when Crystal::ModuleDef
        visit_defs(node.body, infos, qualify_type_name(node.name.to_s, namespace))
      when Crystal::Def
        infos << DefInfo.new(owner: namespace, definition: node, class_method: !node.receiver.nil?)
      end
    end

    private def type_defs : Array(TypeDefInfo)
      infos = [] of TypeDefInfo
      visit_type_defs(parsed_ast, infos)
      infos
    end

    private def visit_type_defs(node : Crystal::ASTNode, infos : Array(TypeDefInfo), namespace : String? = nil)
      case node
      when Crystal::Expressions
        node.expressions.each { |expression| visit_type_defs(expression, infos, namespace) }
      when Crystal::ClassDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        infos << TypeDefInfo.new(type_name, node.location, node.name_location, node.name.to_s.size)
        visit_type_defs(node.body, infos, type_name)
      when Crystal::ModuleDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        infos << TypeDefInfo.new(type_name, node.location, node.name_location, node.name.to_s.size)
        visit_type_defs(node.body, infos, type_name)
      when Crystal::EnumDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        infos << TypeDefInfo.new(type_name, node.location, node.name_location, node.name.to_s.size)
      when Crystal::AnnotationDef
        type_name = qualify_type_name(node.name.to_s, namespace)
        infos << TypeDefInfo.new(type_name, node.location, node.name_location, node.name.to_s.size)
      end
    end

    private def parsed_ast : Crystal::ASTNode
      parser = Crystal::Parser.new(@source)
      parser.wants_doc = false
      parser.filename = @file_uri.decoded_path
      parser.parse
    end

    private def qualify_type_name(name : String, namespace : String?) : String
      return name if namespace.nil? || name.includes?("::")
      "#{namespace}::#{name}"
    end

    private def token_span(line : String) : {Int32, Int32}?
      index = normalized_column(line)
      return unless index
      return unless Resolver.token_char?(line[index])

      start_index = index
      while start_index > 0 && Resolver.token_char?(line[start_index - 1])
        start_index -= 1
      end

      end_index = index + 1
      while (char = line[end_index]?) && Resolver.token_char?(char)
        end_index += 1
      end

      {start_index, end_index}
    end

    private def normalized_column(line : String) : Int32?
      return if line.empty?

      index = @column_number
      index = line.size - 1 if index >= line.size
      return if index < 0

      return index if Resolver.token_char?(line[index])
      return index - 1 if index > 0 && Resolver.token_char?(line[index - 1])

      nil
    end
  end
end
