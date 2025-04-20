require "../diagnostics"
require "./cursor_visitor"
require "./submodule_visitor"

module Crystalline::Analysis
  {% if flag?(:preview_mt) %}
    @@dedicated_thread : Thread = Thread.new(name: "crystalline-dedicated-thread") do
      scheduler = Thread.current.scheduler
      scheduler.run_loop
    end
  {% end %}

  private def self.spawn_dedicated(*, name : String? = nil, &block)
    fiber = Fiber.new(name, &block)
    {% if flag?(:preview_mt) %} fiber.set_current_thread(@@dedicated_thread) {% end %}
    fiber.enqueue
    fiber
  end

  # Compile a target *file_uri*.
  def self.compile(server : LSP::Server, file_uri : URI, *, lib_path : String? = nil, file_overrides : Hash(String, String)? = nil, ignore_diagnostics = false, wants_doc = false, fail_fast = false, top_level = false, compiler_flags : Array(String) = [] of String)
    if file_uri.scheme == "file"
      file = File.new file_uri.decoded_path
      sources = [
        Crystal::Compiler::Source.new(file_uri.decoded_path, file.gets_to_end),
      ]
      file.close
      self.compile(server, sources, lib_path: lib_path, file_overrides: file_overrides, ignore_diagnostics: ignore_diagnostics, wants_doc: wants_doc, top_level: top_level, compiler_flags: compiler_flags)
    end
  end

  # Compile an array of *sources*.
  def self.compile(server : LSP::Server, sources : Array(Crystal::Compiler::Source), *, lib_path : String? = nil, file_overrides : Hash(String, String)? = nil, ignore_diagnostics = false, wants_doc = false, fail_fast = false, top_level = false, compiler_flags : Array(String) = [] of String)
    diagnostics = Diagnostics.new
    reply_channel = Channel(Crystal::Compiler::Result | Exception).new

    # LSP::Log.info { "sources: #{sources.map(&.filename)}" }
    # LSP::Log.info { "lib_path: #{lib_path}" }
    LSP::Log.info { "compiler_flags: #{compiler_flags}" }

    # Delegate heavy processing to a separate thread.
    spawn_dedicated do
      dev_null = File.open(File::NULL, "w")
      compiler = Crystal::Compiler.new
      compiler.no_codegen = true
      compiler.color = false
      compiler.no_cleanup = true
      compiler.file_overrides = file_overrides
      compiler.wants_doc = wants_doc
      compiler.stdout = dev_null
      compiler.stderr = dev_null
      compiler.flags = compiler_flags

      if lib_path_override = lib_path
        path = Crystal::CrystalPath.default_path_without_lib.split(Process::PATH_DELIMITER)
        path.insert(0, lib_path_override)
        compiler.crystal_path = Crystal::CrystalPath.new(path)
      end

      reply = begin
        if top_level
          # Top level only.
          compiler.top_level_semantic(sources)
        elsif fail_fast
          # Regular parser + semantic analysis phases.
          compiler.compile(sources, "")
        else
          # Error tolerant means that errors are collected instead of throwing during the semantic phase, and we still get a partially typed AST back.
          compiler.error_tolerant_compile(sources, "")
        end
      end
      reply_channel.send(reply)
    rescue e : Exception
      reply_channel.send(e)
    ensure
      dev_null.try &.close
    end
    result = reply_channel.receive

    raise result if result.is_a? Exception

    unless ignore_diagnostics
      result.program.requires.each do |path|
        diagnostics.init_value("file://#{path}")
      end

      result.program.error_stack.try &.each do |e|
        diagnostics.append_from_exception(e) if e.is_a?(Crystal::TypeException) || e.is_a?(Crystal::SyntaxException)
      end
    end

    result
  rescue e : Exception
    if e.is_a?(Crystal::TypeException) || e.is_a?(Crystal::SyntaxException)
      LSP::Log.debug(exception: e) { "#{e}" }
      diagnostics.try &.append_from_exception(e) unless ignore_diagnostics
    else
      LSP::Log.debug(exception: e) { "#{e.message}\n#{e.backtrace?}" }
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
          Utils.locations_from_path(node, nodes)
        elsif node.is_a? Crystal::Union
          Utils.locations_from_union(node, nodes)
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

  def self.context_at(result : Crystal::Compiler::Result, location : Crystal::Location) : Hash(String, Crystal::Type)?
    Crystal::ContextVisitor.new(location).process(result).contexts.try &.last?
  end
end
