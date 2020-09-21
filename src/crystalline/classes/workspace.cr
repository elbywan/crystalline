require "compiler/crystal/**"
require "uri"
require "yaml"
require "./text_document"
require "./progress"
require "./result_cache"

class Crystalline::Workspace
  @result_cache : Crystalline::ResultCache = Crystalline::ResultCache.new
  getter root_uri : URI?
  getter opened_documents = {} of String => TextDocument
  getter dependencies : Set(String) = Set(String).new
  getter? entry_point : URI do
    root_uri.try { |uri|
      path = Path[uri.decoded_path, "shard.yml"]
      shards_yaml = File.open(path) do |file|
        YAML.parse(file)
      end
      shard_name = shards_yaml["name"].as_s
      relative_main = shards_yaml.dig?("crystalline", "main").try &.as_s
      relative_main ||= shards_yaml.dig?("targets", shard_name, "main").try &.as_s
      if relative_main && File.exists? relative_main
        main_path = Path[uri.decoded_path, relative_main]
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

  def update_document(params : LSP::DidChangeTextDocumentParams)
    file_uri = params.text_document.uri
    @opened_documents[file_uri]?.try { |document|
      params.content_changes.last?.try { |last_change|
        document.contents = last_change.text
      }
    }
    @result_cache.invalidate(file_uri)
    entry_point?.try { |entry|
      @result_cache.invalidate(entry.to_s)
    } if inside_workspace?(URI.parse file_uri)
  end

  def close_document(params : LSP::DidCloseTextDocumentParams)
    @opened_documents.delete(params.text_document.uri)
  end

  def save_document(server : LSP::Server, params : LSP::DidSaveTextDocumentParams)
    file_uri = params.text_document.uri
    @result_cache.invalidate(file_uri)
    self.compile(server, URI.parse file_uri)
  end

  def format_document(params : LSP::DocumentFormattingParams) : {String, TextDocument}?
    @opened_documents[params.text_document.uri]?.try { |document|
      {Crystal.format(document.contents), document}
    }
  end

  def format_document(params : LSP::DocumentRangeFormattingParams) : {String, TextDocument}?
    @opened_documents[params.text_document.uri]?.try { |document|
      range = params.range
      contents_lines = document.contents.lines(chomp: false)[range.start.line..range.end.line]
      contents_lines[-1] = contents_lines.last[...range.end.character] if range.end.character > 0
      contents_lines[0] = contents_lines.first[range.start.character...]
      {Crystal.format(contents_lines.join), document}
    }
  end

  private def inside_workspace?(file_uri : URI)
    entry_point? && dependencies.size > 0 && file_uri.decoded_path.in?(dependencies)
  end

  @compilation_queue = Set(String).new
  @compilation_queue_lock = Mutex.new

  def recalculate_dependencies(server)
    return unless target = entry_point?

    Analysis.compile(server, target, ignore_diagnostics: true, wants_doc: false, top_level: true).try { |result|
      ConcreteSemanticVisitor.new(result.program).visit(result.node)
      @dependencies = result.program.requires
    }
  rescue
    nil
  end

  def compile(server : LSP::Server, file_uri : URI? = nil, *, in_memory = false, synchronous = false, ignore_diagnostics = false, wants_doc = false, text_overrides = nil, permissive = false, top_level = false)
    return nil unless file_uri || entry_point?

    recalculate_dependencies(server) if dependencies.size < 2

    if external_file = file_uri.try { |uri| !inside_workspace?(uri) }
      target = file_uri.not_nil!
      progress = Progress.new(
        token: "workspace/compile",
        title: "Building",
        message: target.decoded_path
      )
    else
      target = entry_point?.not_nil!
      progress = Progress.new(
        token: "workspace/compile",
        title: "Building workspace",
        message: target.decoded_path
      )
    end

    @compilation_queue_lock.synchronize do
      if @compilation_queue.includes? target.decoded_path
        return nil
      else
        @compilation_queue.add(target.decoded_path)
      end
    end

    file_overrides = nil
    sources = nil
    if in_memory
      file_overrides = Hash(String, String).new
      @opened_documents.each { |uri_str, text_document|
        contents = text_overrides.try(&.[uri_str]?) || text_document.contents
        if target.to_s == uri_str
          sources = [
            Crystal::Compiler::Source.new(target.decoded_path, contents),
          ]
        end
        file_path = URI.parse(uri_str).decoded_path
        file_overrides[file_path] = contents
      }
    end

    if synchronous
      sync_channel = Channel(Crystal::Compiler::Result?).new
    end

    progress.report(server) do
      result = @result_cache.get(target.to_s)
      if result
        @compilation_queue_lock.synchronize {
          @compilation_queue.delete target.decoded_path
        }
      else
        result = Analysis.compile(server, sources.try { |s| s } || target, file_overrides: file_overrides, ignore_diagnostics: ignore_diagnostics, wants_doc: wants_doc, permissive: permissive, top_level: top_level) {
          @compilation_queue_lock.synchronize {
            @compilation_queue.delete target.decoded_path
          }
        }
      end

      if result
        unless external_file
          @dependencies = result.program.requires
        end
        @result_cache.set(target.to_s, result)
        "Completed successfully."
      else
        "Completed with errors."
      end
    ensure
      sync_channel.try &.send(result)
    end

    sync_channel.try &.receive
  end

  private def format_def(d : Crystal::Def | Crystal::Macro)
    arguments = d.args.map &.to_s
    if block_arg = d.block_arg
      arguments << block_arg.to_s
    elsif d.is_a? Crystal::Def && d.yields
      arguments << "&block"
    end
    type = begin
      d.type?.to_s
    rescue e
      # LSP::Log.error(exception: e) { e.to_s }
      "Nil"
    end
    "#{d.visibility.to_s.downcase} #{d.name}(#{arguments.join ", "}) : #{type}"
  rescue e
    # LSP::Log.error(exception: e) { e.to_s}
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
    result = self.compile(server, file_uri, in_memory: true, synchronous: true, ignore_diagnostics: true, wants_doc: true, permissive: true)
    location = Crystal::Location.new(
      file_uri.decoded_path,
      line_number: position.line + 1,
      column_number: position.character + 1
    )
    result.try { |r|
      Analysis.nodes_at_cursor(r, location)
    }.try do |nodes, context|
      n = nodes.last?
      contents = [] of String

      # LSP::Log.info { "Node at cursor: #{n}" }
      # LSP::Log.info { "Node class: #{n.class}" }
      # LSP::Log.info { "Node type: #{n.try &.type?}" }
      # LSP::Log.info { "Node type class: #{n.try &.type?.try &.class}" }
      # LSP::Log.info { "Nodes classes: #{nodes.map &.class}"}
      # LSP::Log.info { "Context: #{context}" }

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
    result = self.compile(server, file_uri, in_memory: true, synchronous: true, ignore_diagnostics: true, wants_doc: true, permissive: true)
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
    # if trigger_character
    #   prefix = document_lines[position.line][0...position.character].rstrip(trigger_character)
    #   suffix = document_lines[position.line][(position.character)..]?
    #   left_offset = position.character - prefix.size
    #   right_offset = 0
    # else
      left_offset = 0
      right_offset = 0

      if trigger_character
        prefix = document_lines[position.line][0...position.character].rstrip(trigger_character)
        left_offset = position.character - prefix.size
      else
        document_lines[position.line][0...position.character].each_char_with_index { |char, index|
          case char
          when '.', ':', ' ', '(', ')', '[', ']', '{', '}', ';'
            trigger_character = char.to_s
            left_offset = position.character - index
          end
        }
        prefix = document_lines[position.line][0...(position.character - left_offset)]
      end

      # if trigger_character
      #   prefix = document_lines[position.line][0...position.character].rstrip(trigger_character)
      # else
      #   prefix = document_lines[position.line][0...position.character]
      # end
      # suffix = document_lines[position.line][(position.character)..]?

      # prefix = document_lines[position.line][0...(position.character - left_offset)]
      suffix = document_lines[position.line][(position.character)..]?

      suffix.try &.each_char_with_index { |char, index|
        unless char.ascii_alphanumeric? || char == '_' || char == '?' || char == '!' || char == ':'
          right_offset = index
          break
        end
      # case char
      # when ' ', ')', ']', '}', '\n', ';', '(', '{', '['
      #   right_offset = index
      #   break
      # when '.', ':'
      #   right_offset = index - 1
      #   break
      # end
      }
      suffix = suffix.try &.[right_offset...]?
    # end

    # LSP::Log.info { "prefix(left offset #{left_offset}): #{prefix}"}
    # LSP::Log.info { "suffix(right offset #{right_offset}): #{suffix}"}
    # LSP::Log.info { "trigger character: #{trigger_character}"}

    document_lines[position.line] = prefix + (suffix || "")
    text_overrides = {
      file_uri.to_s => document_lines.join,
    }

    location = Crystal::Location.new(
      file_uri.decoded_path,
      line_number: position.line + 1,
      column_number: position.character - left_offset
    )

    # Temporary until on the fly context completion can be handled
    return unless trigger_character == "." || trigger_character == ":"

    result = self.compile(server, file_uri, in_memory: true, synchronous: true, ignore_diagnostics: false, wants_doc: true, text_overrides: text_overrides, permissive: true)
    return unless result

    # source = Crystal::Compiler::Source.new(target.decoded_path, document_lines.join)
    # program = result.program
    # parser = Crystal::Parser.new(source.code, program.string_pool)
    # parser.filename = source.filename
    # parser.wants_doc = true
    # nodes = parser.parse

    # LSP::Log.info { "Parser result: #{!nodes.nil?}"}

    # semantic_ast = program.semantic(nodes)

    # LSP::Log.info { "Semantic AST: #{!semantic_ast.nil?}"}

    # semantic_ast.try { |ast|
    #   visitor = CursorVisitor.new(location)
    #   ast.accept(visitor)
    #   visitor.nodes.last?
    # }.try { |n|
    #   LSP::Log.info { "Node at cursor: #{n}" }
    #   LSP::Log.info { "Node type: #{n.type}" }
    # }

    nodes, _ = Analysis.nodes_at_cursor(result, location)
    nodes.last?.try do |n|
      completion_items = [] of LSP::CompletionItem

      # LSP::Log.info { "Node at cursor: #{n}" }
      # LSP::Log.info { "Node class: #{n.class}" }
      # LSP::Log.info { "Node type: #{n.type?}" }
      # LSP::Log.info { "Node type class: #{n.type?.try &.class}" }
      # LSP::Log.info { "Node type defs: #{n.type?.try &.defs}" }

      range = LSP::Range.new({
        start: LSP::Position.new({line: position.line, character: position.character - left_offset}),
        end:   LSP::Position.new({line: position.line, character: position.character + right_offset}),
      })

      case trigger_character
      when "."
        if n.type?.responds_to? :defs
          Analysis.all_defs(n.type).each { |def_name, definition, owner_type, nesting|
            owner_prefix = "*Inherited from: #{owner_type.name}*\n\n" if owner_type.responds_to? :name && owner_type != n.type
            owner_prefix ||= ""
            documentation = (owner_prefix + (definition.doc || ""))

            # text_edit = LSP::TextEdit.new({
            #   range:    range,
            #   new_text: def_name,
            # })

            completion_items << LSP::CompletionItem.new({
              label:  def_name,
              kind:   LSP::CompletionItemKind::Function,
              detail: format_def(definition),
              # text_edit: text_edit,
              sort_text: (nesting + 1).chr.to_s + def_name,
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

            completion_items << LSP::CompletionItem.new({
              label:  macro_name,
              kind:   LSP::CompletionItemKind::Method,
              detail: format_def(macro_def),
              # text_edit: text_edit,
              sort_text: (nesting + 1).chr.to_s + macro_name,
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
              new_text: type_string.lchop(node_type.to_s),
            })

            completion_items << LSP::CompletionItem.new({
              label:         type_string,
              text_edit:     text_edit,
              kind:          LSP::CompletionItemKind::Module,
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
        # Analysis.context_at(result, location).try &.each { |contexts|
        #   contexts.each { |name, type|
        #     label = "#{name} : #{type}"
        #     LSP::Log.info { label }
        #     text_edit = LSP::TextEdit.new({
        #       range:    range,
        #       new_text: label,
        #     })
        #     completion_items << LSP::CompletionItem.new({
        #       label: label,
        #       text_edit: text_edit,
        #       kind: LSP::CompletionItemKind::Variable,
        #       documentation: type.doc.try { |doc|
        #         LSP::MarkupContent.new({
        #           kind: LSP::MarkupKind::MarkDown,
        #           value: doc
        #         })
        #       }
        #     })
        #   }
        # }
      end

      selected_element_index = nil
      completion_items.each_with_index do |elt, i|
        sort_text = elt.sort_text || elt.label
        selected_element_index ||= i
        target = completion_items[selected_element_index].try { |elt| elt.sort_text || elt.label }
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
