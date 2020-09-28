require "compiler/crystal/**"
require "../diagnostics"
require "./cursor_visitor"
require "./submodule_visitor"
require "./concrete_semantic_visitor"

module Crystalline::Analysis
  # Compile a target *file_uri*.
  def self.compile(server : LSP::Server, file_uri : URI, *, file_overrides : Hash(String, String)? = nil, ignore_diagnostics = false, wants_doc = false, permissive = false, top_level = false)
    if file_uri.scheme == "file"
      file = File.new file_uri.decoded_path
      sources = [
        Crystal::Compiler::Source.new(file_uri.decoded_path, file.gets_to_end),
      ]
      file.close
      self.compile(server, sources, file_overrides: file_overrides, ignore_diagnostics: ignore_diagnostics, wants_doc: wants_doc, permissive: permissive, top_level: top_level)
    end
  end

  # Compile an array of *sources*.
  def self.compile(server : LSP::Server, sources : Array(Crystal::Compiler::Source), *, file_overrides : Hash(String, String)? = nil, ignore_diagnostics = false, wants_doc = false, permissive = false, top_level = false)
    diagnostics = Diagnostics.new
    reply_channel = Channel(Crystal::Compiler::Result | Exception).new

    # Delegate heavy processing to a separate thread.
    Thread.new do
      kill_thread = Channel(Nil).new
      spawn same_thread: true do
        compiler = Crystal::Compiler.new
        compiler.no_codegen = true
        compiler.color = false
        compiler.no_cleanup = true
        compiler.file_overrides = file_overrides
        compiler.wants_doc = wants_doc
        result = begin
          if top_level
            # Top level only.
            compiler.top_level_semantic(sources)
          elsif permissive
            # Permissive means that if an error is thrown during the semantic phase, we still get a partially typed AST back.
            compiler.permissive_compile(sources, "")
          else
            # Regular parser + semantic analysis phases.
            compiler.compile(sources, "")
          end
        end
        reply_channel.send(result)
      rescue e : Exception
        reply_channel.send(e)
      ensure
        kill_thread.send nil
      end
      kill_thread.receive
    end
    result = reply_channel.receive

    raise result if result.is_a? Exception
    result.program.requires.each { |path|
      diagnostics.init_value("file://#{path}")
    }
    result
  rescue e : Exception
    if e.is_a?(Crystal::TypeException) || e.is_a?(Crystal::SyntaxException)
      LSP::Log.debug(exception: e) { "#{e}" }
      diagnostics.try &.append_from_exception(e) unless ignore_diagnostics
    else
      LSP::Log.debug(exception: e) { "#{e}\n#{e.backtrace?}" }
    end
    nil
  ensure
    # Propagate diagnostics to the client.
    diagnostics.try &.publish(server) unless ignore_diagnostics
  end

  # Return the node at the given *location*.
  def self.node_at_cursor(result : Crystal::Compiler::Result, location : Crystal::Location) : Crystal::ASTNode?
    nodes, _ = CursorVisitor.new(location).process(result)
    nodes.last?
  end

  # Return the whole hierarchy of nodes at the given *location*.
  def self.nodes_at_cursor(result : Crystal::Compiler::Result, location : Crystal::Location) : {Array(Crystal::ASTNode), Hash(String, {Crystal::Type?, Crystal::Location?})}
    CursorVisitor.new(location).process(result)
  end

  record Definitions, node : Crystal::ASTNode, locations : Array({Crystal::Location, Crystal::Location})?

  # Return the possible definition for the node at the given *location*.
  def self.definitions_at_cursor(result : Crystal::Compiler::Result, location : Crystal::Location) : Definitions?
    nodes, context = CursorVisitor.new(location).process(result)
    nodes.last?.try { |node|
      LSP::Log.debug { "Class of node at cursor: #{node.class} " }
      locations = begin
        if node.is_a? Crystal::Call
          if defs = node.target_defs
            defs.compact_map { |d|
              start_location = d.location.try { |loc| loc.expanded_location || loc }.not_nil!
              end_location = d.end_location.try { |loc| loc.expanded_location || loc }.not_nil!
              {start_location, end_location}
            }
          elsif expanded_macro = node.expanded_macro
            start_location = expanded_macro.location.try { |loc| loc.expanded_location || loc }.not_nil!
            end_location = expanded_macro.end_location.try { |loc| loc.expanded_location || loc } || start_location
            [{start_location, end_location}]
          end
        elsif node.is_a? Crystal::Require
          location = node.location
          filename = node.string
          relative_to = location.try &.original_filename
          filenames = result.program.find_in_path(filename, relative_to)
          filenames.try &.map { |path|
            location = Crystal::Location.new(
              path,
              line_number: 1,
              column_number: 1
            )
            {location, location}
          }
        elsif node.is_a? Crystal::Path
          target = self.resolve_path(node, nodes)
          # LSP::Log.info { "Path target: #{target} "} if target
          # LSP::Log.info { "Path type: #{node.type?} "}
          target.as?(Crystal::Const | Crystal::Type).try &.locations.try &.map do |location|
            end_location = Crystal::Location.new(
              location.filename,
              line_number: location.line_number + 1,
              column_number: 0
            )
            {location, end_location}
          end
        elsif node.is_a? Crystal::Var
          if definition = context[node.to_s]?
            _, location = definition
            [{location, location}] if location
          end
        elsif node.is_a? Crystal::InstanceVar
          if ivar = context["self"]?.try &.[0].try &.lookup_instance_var? node.name
            if location = ivar.location
              [{location, location}]
            end
          end
        elsif node.is_a? Crystal::ClassVar
          if cvar = context["self"]?.try &.[0].try &.all_class_vars[node.name]? # lookup_raw_class_var? node.name
            if (location = cvar.location)
              [{location, location}]
            end
          end
        end
      end

      Definitions.new(node: node, locations: locations)
    }
  end

  def self.all_defs(type, *, accumulator = [] of {String, Crystal::Def, Crystal::Type, Int32}, nesting = 0)
    if type.is_a? Crystal::UnionType
      # TODO: intersection instead of union
      type.union_types.each { |t|
        all_defs(t, accumulator: accumulator, nesting: nesting)
      }
      return accumulator.uniq &.[1]
    end

    type.defs.try &.each do |def_name, defs_with_metadata|
      defs_with_metadata.each do |def_with_metadata|
        definition = def_with_metadata.def
        body = definition.body

        next if body.is_a?(Crystal::Primitive) && body.name == "allocate"
        next if def_name == "set_crystal_type_id"

        accumulator << {def_name, definition, type, nesting}
      end
    end

    type.parents.try &.each do |parent|
      if type.responds_to? :instance_type
        extends_self = type.instance_type == parent
      end
      self.all_defs(parent, accumulator: accumulator, nesting: extends_self ? nesting : nesting + 1)
    end

    accumulator
  end

  def self.all_macros(type, *, accumulator = [] of {String, Crystal::Macro, Crystal::Type, Int32}, nesting = 0)
    if type.is_a? Crystal::UnionType
      type.union_types.each { |t|
        all_macros(t, accumulator: accumulator, nesting: nesting)
      }
      return accumulator.uniq &.[0]
    end

    type.macros.try &.each do |macro_name, macros|
      macros.each do |macro_def|
        accumulator << {macro_name, macro_def, type, nesting}
      end
    end

    type.parents.try &.each do |parent|
      self.all_macros(parent, accumulator: accumulator, nesting: nesting + 1)
    end

    accumulator
  end

  def self.all_submodules(result : Crystal::Compiler::Result, module_type : Crystal::Type) : Array(Crystal::ModuleType)
    SubModuleVisitor.new(module_type).process_result(result)
  end

  def self.context_at(result : Crystal::Compiler::Result, location : Crystal::Location) : Crystal::HashStringType?
    Crystal::ContextVisitor.new(location).process(result).contexts.try &.last?
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
