require "compiler/crystal/**"
require "uri"
require "yaml"
require "./text_document"
require "./progress"
require "./result_cache"

class Crystalline::Workspace
  # The previous compilation results, indexed by compilation entry point.
  @result_cache : Crystalline::ResultCache = Crystalline::ResultCache.new
  # The workspace filesystem uri.
  getter root_uri : URI?
  # A list of documents that are openened in the text editor.
  getter opened_documents = {} of String => TextDocument
  # The dependencies of the workspace, meaning the list of files required by the compilation target (entry point).
  getter dependencies : Set(String) = Set(String).new
  # Determines the workspace entry point.
  getter? entry_point : URI do
    root_uri.try { |uri|
      path = Path[uri.decoded_path, "shard.yml"]
      shards_yaml = File.open(path) do |file|
        YAML.parse(file)
      end
      shard_name = shards_yaml["name"].as_s
      # If shard.yml has the `crystalline/main` key, use that.
      relative_main = shards_yaml.dig?("crystalline", "main").try &.as_s
      # Else if shard.yml has a `targets/[shard name]/main` key, use that.
      relative_main ||= shards_yaml.dig?("targets", shard_name, "main").try &.as_s
      if relative_main && File.exists? relative_main
        main_path = Path[uri.decoded_path, relative_main]
        # Add the entry point as a dependency to itself.
        dependencies << main_path.to_s
        URI.parse("file://#{main_path}")
      end
    }
  rescue e
    nil
  end

  def initialize(server : LSP::Server, root_uri : String?)
    @root_uri = root_uri.try &->URI.parse(String)
  end

  def open_document(params : LSP::DidOpenTextDocumentParams)
    raw_uri = params.text_document.uri
    document = TextDocument.new(raw_uri, params.text_document.text)
    @opened_documents[raw_uri] = document
  end

  def update_document(server : LSP::Server, params : LSP::DidChangeTextDocumentParams)
    file_uri = params.text_document.uri
    @opened_documents[file_uri]?.try { |document|
      content_changes = params.content_changes.map { |change|
        { change.text, change.range }
      }
      document.update_contents(content_changes, version: params.text_document.version)
    }
    @result_cache.invalidate(file_uri)
    entry_point?.try { |entry|
      @result_cache.invalidate(entry.to_s)
    } if inside_workspace?(URI.parse file_uri)
    # spawn self.compile(server, URI.parse(file_uri), in_memory: true )
  end

  def close_document(params : LSP::DidCloseTextDocumentParams)
    @opened_documents.delete(params.text_document.uri)
  end

  def save_document(server : LSP::Server, params : LSP::DidSaveTextDocumentParams)
    file_uri = params.text_document.uri
    @result_cache.invalidate(file_uri)
    # spawn is needed because we are inside a lock
    # and compilation should not prevent unlocking the mutex
    spawn self.compile(server, URI.parse(file_uri), discard_nil_cached_result: true)
  end

  def format_document(params : LSP::DocumentFormattingParams) : {String, TextDocument}?
    @opened_documents[params.text_document.uri]?.try { |document|
      {Crystal.format(document.contents), document}
    }
  rescue e
    # swallow exceptions silently
  end

  def format_document(params : LSP::DocumentRangeFormattingParams) : {String, TextDocument}?
    @opened_documents[params.text_document.uri]?.try { |document|
      range = params.range
      contents_lines = document.contents.lines(chomp: false)[range.start.line..range.end.line]
      contents_lines[-1] = contents_lines.last[...range.end.character] if range.end.character > 0
      contents_lines[0] = contents_lines.first[range.start.character...]
      {Crystal.format(contents_lines.join), document}
    }
  rescue e
    # swallow exceptions silently
  end

  private def inside_workspace?(file_uri : URI)
    entry_point? && dependencies.size > 0 && file_uri.decoded_path.in?(dependencies)
  end

  # Run a top level semantic analysis to compute dependencies.
  def recalculate_dependencies(server)
    return unless target = entry_point?

    Analysis.compile(server, target, ignore_diagnostics: true, wants_doc: false, top_level: true).try { |result|
      ConcreteSemanticVisitor.new(result.program).visit(result.node)
      @dependencies = result.program.requires
    }
  rescue
    nil
  end

  # Allow one compilation at a time.
  class_getter compilation_lock = Mutex.new

  # Use the crystal compiler to typecheck the program.
  def compile(server : LSP::Server, file_uri : URI? = nil, *, in_memory = false, ignore_diagnostics = false, wants_doc = false, text_overrides = nil, permissive = true, top_level = false, discard_nil_cached_result = false)
    # We need a target.
    return nil unless file_uri || entry_point?

    # If the workspace entry point has less than 1 dependency, it could mean that the last dependency calculation failed (likely because of a syntax error).
    # So we try again.
    recalculate_dependencies(server) if dependencies.size < 2

    if external_file = file_uri.try { |uri| !inside_workspace?(uri) }
      # If the file is not a workspace dependency.
      target = file_uri.not_nil!
      progress = Progress.new(
        token: "workspace/compile",
        title: "Building",
        message: target.decoded_path
      )
    else
      # File is a dependency.
      target = entry_point?.not_nil!
      progress = Progress.new(
        token: "workspace/compile",
        title: "Building workspace",
        message: target.decoded_path
      )
    end

    target_string = target.to_s
    # Check we can serve the result from the cache.
    if @result_cache.exists?(target_string) && !@result_cache.invalidated?(target_string)
      cached_result = @result_cache.get(target_string)
      return cached_result unless cached_result.nil? && discard_nil_cached_result
    end

    # Wait for pending compilations to finish…
    @@compilation_lock.synchronize do
      # Check again the cache in case some previous compilation that ran while waiting for the mutex to unlock is still valid.
      if @result_cache.exists?(target_string) && !@result_cache.invalidated?(target_string)
        cached_result = @result_cache.get(target_string)
        return cached_result unless cached_result.nil? && discard_nil_cached_result
      end

      sync_channel = Channel(Crystal::Compiler::Result?).new

      progress.report(server) do
        file_overrides = nil
        sources = nil
        # Store the start of the compilation.
        compilation_start = @result_cache.monotonic_now
        if in_memory
          # Tell the compiler to load the opened files from memory, not from the filesystem.
          file_overrides = Hash(String, String).new
          @opened_documents.each { |uri_str, text_document|
            contents = text_overrides.try(&.[uri_str]?) || text_document.contents
            if target_string == uri_str
              # If the entry point itself needs to be loaded from memory.
              sources = [
                Crystal::Compiler::Source.new(target.decoded_path, contents),
              ]
            end
            file_path = URI.parse(uri_str).decoded_path
            file_overrides[file_path] = contents
          }
        end
        result = Analysis.compile(server, sources || target, file_overrides: file_overrides, ignore_diagnostics: ignore_diagnostics, wants_doc: wants_doc, top_level: top_level)
        # Store the result in the cache, unless a client event invalided the previous cache.
        # For instance if a compilation is running, but the user saved the document in the meantime (before completion)
        # then we discard the result because it is already outdated.
        @result_cache.set(target_string, result, unless_invalidated_since: compilation_start)

        if result
          unless external_file
            # Store the workspace dependencies.
            @dependencies = result.program.requires
          end
          "Completed successfully."
        else
          "Completed with errors."
        end
      ensure
        sync_channel.send(result)
      end

      select
      when result = sync_channel.receive
        result
      # Just in case…
      when timeout 60.seconds
        nil
      end
    end
  end

  # Format a method definition or macro.
  private def format_def(d : Crystal::Def | Crystal::Macro, *, short = false)
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

  private def append_markdown_doc(contents : Array(String), doc : String?)
    if doc
      contents << "----------"
      contents << <<-MARKDOWN
      #{doc}
      MARKDOWN
    end
  end

  private def code_markdown(str : String?, *, language = "") : String
    if str
      <<-MARKDOWN
      ```#{language}
      #{str}
      ```
      MARKDOWN
    else
      ""
    end
  end

  def hover(server : LSP::Server, file_uri : URI, position : LSP::Position)
    result = self.compile(server, file_uri, in_memory: true, ignore_diagnostics: true, wants_doc: true)
    location = Crystal::Location.new(
      file_uri.decoded_path,
      line_number: position.line + 1,
      column_number: position.character + 1
    )
    result.try { |r|
      Analysis.nodes_at_cursor(r, location)
    }.try do |nodes, _context|
      n = nodes.last?
      contents = [] of String

      # LSP::Log.info { "Node at cursor: #{n}" }
      # LSP::Log.info { "Node class: #{n.class}" }
      # LSP::Log.info { "Node type: #{n.try &.type?}" }
      # LSP::Log.info { "Node type class: #{n.try &.type?.try &.class}" }
      # LSP::Log.info { "Nodes classes: #{nodes.map &.class}" }
      # LSP::Log.info { "Context: #{_context}" }

      if n.is_a? Crystal::Def || n.is_a? Crystal::Macro
        contents << code_markdown(format_def(n), language: "crystal")
        append_markdown_doc contents, n.doc
      elsif n.responds_to? :resolved_type
        str = ""
        if n.responds_to? :name
          str += "#{n.name}: #{n.resolved_type}"
        else
          str += n.resolved_type.to_s
          str = n.to_s if str.empty?
        end
        contents << code_markdown(str, language: "crystal")
        append_markdown_doc contents, n.resolved_type.doc
      elsif n.is_a? Crystal::Call
        if definition = n.target_defs.try &.first?
          contents << code_markdown(format_def(definition), language: "crystal")
        elsif n.expanded && n.expanded_macro
          contents << code_markdown(n.expanded.to_s, language: "crystal")
        end
        append_markdown_doc contents, (definition || n.expanded_macro).try &.doc
      elsif n.is_a? Crystal::Path
        node_type = n.type? || Analysis.resolve_path(n, nodes)
        if node_type
          contents << code_markdown(node_type.to_s, language: "crystal")
          append_markdown_doc contents, node_type.doc
        end
      elsif n
        str = ""
        if n.responds_to? :name
          str += "#{n.name}: #{n.type? || "?"}"
        else
          str += n.type?.to_s
          str = n.to_s if str.empty?
        end
        contents << code_markdown(str, language: "crystal")
        append_markdown_doc contents, n.doc
      end

      LSP::Hover.new({
        contents: LSP::MarkupContent.new({
          kind:  LSP::MarkupKind::MarkDown,
          value: contents.join "\n",
        }),
      })
    end
  rescue
    nil
  end

  def definitions(server : LSP::Server, file_uri : URI, position : LSP::Position)
    result = self.compile(server, file_uri, in_memory: true, ignore_diagnostics: true, wants_doc: true)
    location = Crystal::Location.new(
      file_uri.decoded_path,
      line_number: position.line + 1,
      column_number: position.character + 1
    )
    result.try { |r|
      Analysis.definitions_at_cursor(r, location)
    }.try do |definitions|
      node = definitions.node
      definitions.locations.try &.map { |start_loc, end_loc|
        if node.is_a? Crystal::Path || node.is_a? Crystal::Require
          target_uri = "file://#{start_loc.original_filename}"
          origin_location = node.location.not_nil!
          origin_end_location = definitions.node.end_location || Crystal::Location.new(
            file_uri.decoded_path,
            line_number: origin_location.line_number + 1,
            column_number: 0
          )

          origin_selection_range = LSP::Range.new({
            start: LSP::Position.new({line: origin_location.line_number - 1, character: origin_location.column_number - 1}),
            end:   LSP::Position.new({line: origin_end_location.line_number - 1, character: origin_end_location.column_number}),
          })
          target_range = LSP::Range.new({
            start: LSP::Position.new({line: start_loc.line_number - 1, character: start_loc.column_number - 1}),
            end:   LSP::Position.new({line: end_loc.line_number - 1, character: end_loc.column_number}),
          })

          LSP::LocationLink.new({
            target_uri:             target_uri,
            origin_selection_range: origin_selection_range,
            target_range:           target_range,
            target_selection_range: target_range,
          })
        else
          LSP::Location.new({
            uri:   "file://#{start_loc.original_filename}",
            range: LSP::Range.new({
              start: LSP::Position.new({line: start_loc.line_number - 1, character: start_loc.column_number - 1}),
              end:   LSP::Position.new({line: end_loc.line_number - 1, character: end_loc.column_number}),
            }),
          })
        end
      }
    end
  rescue
    nil
  end

  def completion(server : LSP::Server, file_uri : URI, position : LSP::Position, trigger_character : String?)
    text_document = @opened_documents[file_uri.to_s]?
    return unless text_document

    # LSP::Log.info { "completion: #{trigger_character}"}

    document_lines = text_document.contents.lines(chomp: false)
    left_offset = 0
    right_offset = 0
    truncate_line = false

    if trigger_character
      # Autocompletion triggered by a special character (. and :)
      # We need to strip every occurence of the special character to please the parser.
      prefix = document_lines[position.line][0...position.character].rstrip(trigger_character)
      left_offset = position.character - prefix.size
    else
      # We need to determine which character (and by extension - autocompletion kind) is best suited depending on the location and its surroundings.
      document_lines[position.line][0...position.character].each_char_with_index { |char, index|
        unless char.ascii_alphanumeric? || char == '_' || char == '?' || char == '!'
          trigger_character = char.to_s
          left_offset = position.character - index
        end
      }
      prefix = document_lines[position.line][0...(position.character - left_offset)]
    end

    suffix = document_lines[position.line][(position.character)..]?

    # Remove the rest of the line (or part of it) to please the parser.
    suffix.try &.each_char_with_index { |char, index|
      unless char.ascii_alphanumeric? || char == '_' || char == '?' || char == '!' || char == ':'
        truncate_line = true if char == '(' || char == '{' || char == '['
        right_offset = index
        break
      end
    }
    suffix = suffix.try &.[right_offset...]?

    # LSP::Log.info { "prefix(left offset #{left_offset}): #{prefix}"}
    # LSP::Log.info { "suffix(right offset #{right_offset}): #{suffix}"}
    # LSP::Log.info { "trigger character: #{trigger_character}"}

    document_lines[position.line] = prefix + (!truncate_line ? (suffix || "\n") : "\n")
    # Force the compiler load the file from this Hash.
    text_overrides = {
      file_uri.to_s => document_lines.join,
    }

    location = Crystal::Location.new(
      file_uri.decoded_path,
      line_number: position.line + 1,
      column_number: position.character - left_offset
    )

    # Trigger a "permissive" compilation.
    result = self.compile(server, file_uri, in_memory: true, ignore_diagnostics: true, wants_doc: true, text_overrides: text_overrides, discard_nil_cached_result: true)
    return unless result

    nodes, _ = Analysis.nodes_at_cursor(result, location)
    nodes.last?.try do |n|
      completion_items = [] of LSP::CompletionItem

      # LSP::Log.info { "Node at cursor: #{n}" }
      # LSP::Log.info { "Node class: #{n.class}" }
      # # LSP::Log.info { "Node type: #{n.type?}" }
      # LSP::Log.info { "Node type class: #{n.type?.try &.class}" }
      # LSP::Log.info { "Node type defs: #{n.type?.try &.defs}" }

      range = LSP::Range.new({
        start: LSP::Position.new({line: position.line, character: position.character - left_offset + 1}),
        end:   LSP::Position.new({line: position.line, character: position.character + right_offset}),
      })

      case trigger_character
      when "."
        # We are looking for methods…
        if n.type?.responds_to? :defs
          Analysis.all_defs(n.type).each { |def_name, definition, owner_type, nesting|
            owner_prefix = "*Inherited from: #{owner_type.name}*\n\n" if owner_type.responds_to? :name && owner_type != n.type
            owner_prefix ||= ""
            documentation = (owner_prefix + (definition.doc || ""))

            text_edit = LSP::TextEdit.new({
              range:    range,
              new_text: def_name,
            })

            completion_items << LSP::CompletionItem.new({
              label:         format_def(definition, short: true),
              insert_text:   def_name,
              kind:          LSP::CompletionItemKind::Function,
              filter_text:   def_name,
              detail:        format_def(definition),
              text_edit:     text_edit,
              sort_text:     (nesting + 1).chr.to_s + def_name,
              documentation: documentation.try { |doc|
                LSP::MarkupContent.new({
                  kind:  LSP::MarkupKind::MarkDown,
                  value: doc,
                })
              },
            })
          }

          Analysis.all_macros(n.type).each { |macro_name, macro_def, owner_type, nesting|
            owner_prefix = "*Inherited from: #{owner_type.name}*\n\n" if owner_type.responds_to? :name && owner_type != n.type
            owner_prefix ||= ""
            documentation = (owner_prefix + (macro_def.doc || ""))

            text_edit = LSP::TextEdit.new({
              range:    range,
              new_text: macro_name,
            })

            completion_items << LSP::CompletionItem.new({
              label:         format_def(macro_def, short: true),
              insert_text:   macro_name,
              kind:          LSP::CompletionItemKind::Method,
              filter_text:   macro_name,
              detail:        format_def(macro_def),
              text_edit:     text_edit,
              sort_text:     (nesting + 1).chr.to_s + macro_name,
              documentation: documentation.try { |doc|
                LSP::MarkupContent.new({
                  kind:  LSP::MarkupKind::MarkDown,
                  value: doc,
                })
              },
            })
          }
        end
      when ":"
        # We are looking for module types…
        node_type = n.type?

        if n.is_a? Crystal::Path
          node_type ||= Analysis.resolve_path(n, nodes)
        end

        if node_type.is_a? Crystal::MetaclassType
          node_type = node_type.instance_type

          Analysis.all_submodules(result, node_type).uniq(&.to_s).each { |type|
            type_string = type.to_s

            text_edit = LSP::TextEdit.new({
              range:    range,
              new_text: type_string.lchop(node_type.to_s).lchop(trigger_character || ':'),
            })

            completion_items << LSP::CompletionItem.new({
              label:         type_string,
              text_edit:     text_edit,
              kind:          Crystalline::Utils.map_completion_kind(type, default: LSP::CompletionItemKind::Module),
              documentation: type.doc.try { |doc|
                LSP::MarkupContent.new({
                  kind:  LSP::MarkupKind::MarkDown,
                  value: doc,
                })
              },
            })
          }
        end
      else
        # Context autocompletion.
        context = Analysis.context_at(result, location)
        if trigger_character == "@"
          context.try &.select! { |name| name.starts_with? "@" }
        end
        context.try &.each { |name, type|
          label = "#{name} : #{type}"
          text_edit = LSP::TextEdit.new({
            range:    range,
            new_text: name.lchop(trigger_character || ""),
          })
          completion_items << LSP::CompletionItem.new({
            label:         label,
            text_edit:     text_edit,
            kind:          LSP::CompletionItemKind::Variable,
            documentation: type.doc.try { |doc|
              LSP::MarkupContent.new({
                kind:  LSP::MarkupKind::MarkDown,
                value: doc,
              })
            },
          })
        }
      end

      selected_element_index = nil
      completion_items.each_with_index do |elt, i|
        sort_text = elt.sort_text || elt.label
        selected_element_index ||= i
        target = completion_items[selected_element_index].try { |e| e.sort_text || e.label }
        if (sort_text <=> target) < 0
          selected_element_index = i
        end
      end

      if selected_element_index
        selected_element = completion_items[selected_element_index]
        selected_element.preselect = true
        completion_items[selected_element_index] = selected_element
      end

      LSP::CompletionList.new({
        is_incomplete: false,
        items:         completion_items,
      })
    end
  rescue
    nil
  end
end
