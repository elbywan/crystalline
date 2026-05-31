require "spec"
require "file_utils"
require "../src/crystalline/requires"
require "../src/crystalline/main"

private def with_workspace_document(source : String)
  root = File.join(Dir.tempdir, "crystalline-workspace-interactive-#{Random::Secure.hex(8)}")
  Dir.mkdir_p(root)
  path = File.join(root, "src", "main.cr")
  Dir.mkdir_p(File.dirname(path))
  File.write(File.join(root, "shard.yml"), <<-YAML)
    name: workspace_interactive
    targets:
      workspace_interactive:
        main: src/main.cr
  YAML
  File.write(path, source)

  begin
    Crystalline::EnvironmentConfig.run
    server = LSP::Server.new(IO::Memory.new, IO::Memory.new)
    workspace = Crystalline::Workspace.new(server, "file://#{root}")
    uri = URI.parse("file://#{path}")
    workspace.opened_documents[uri.to_s] = Crystalline::TextDocument.new(uri, workspace.projects.first?, source)
    yield server, workspace, uri
  ensure
    FileUtils.rm_rf(root)
  end
end

class Crystalline::Workspace
  def seed_semantic_result(key : String, result : Crystal::Compiler::Result)
    @semantic_cache[key] = result
  end

  def seed_result_cache(key : String, result : Crystal::Compiler::Result?)
    @result_cache.set(key, result)
  end

  def result_cache_invalidated?(key : String) : Bool
    @result_cache.invalidated?(key)
  end
end

private def mark_workspace_document_dirty(document : Crystalline::TextDocument, contents : String, version : Int32 = 1)
  document.update_contents([{contents, nil}], version: version)
end

describe Crystalline::Workspace do
  it "does not compile unsupported completion requests without a semantic cache" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class Factory
        def build(name : String) : Greeter
          Greeter.new
        end
      end

      def demo(factory : Factory)
        factory.build("hi").sh
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("factory.build(\"hi\").sh") }
      position = LSP::Position.new(line: line_number, character: lines[line_number].size - 1)

      workspace.completion(server, uri, position, nil).should be_nil
    end
  end

  it "does not compile unsupported hover requests without a semantic cache" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class Factory
        def build(name : String) : Greeter
          Greeter.new
        end
      end

      def demo(factory : Factory)
        factory.build("hi").shout
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("factory.build(\"hi\").shout") }
      character = lines[line_number].rindex("shout").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      workspace.hover(server, uri, position).should be_nil
    end
  end

  it "uses lightweight definitions without a semantic cache" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo(greeter : Greeter)
        greeter.shout
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("greeter.shout") }
      character = lines[line_number].rindex("shout").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      definitions = workspace.definitions(server, uri, position)
      definitions.should_not be_nil
      definitions.not_nil!.size.should be > 0
    end
  end

  it "does not use stale semantic cache for dirty buffers" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo(greeter : Greeter)
        greeter.shout
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      result = Crystalline::Analysis.compile(
        server,
        uri,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil
      workspace.seed_semantic_result(project.entry_point?.not_nil!.to_s, result.not_nil!)

      workspace.opened_documents[uri.to_s].not_nil!.update_contents([
        {"sh", LSP::Range.new(
          start: LSP::Position.new(line: 6, character: 16),
          end: LSP::Position.new(line: 6, character: 21),
        )},
      ], version: 1)

      position = LSP::Position.new(line: 6, character: 18)
      workspace.hover(server, uri, position).should be_nil
      workspace.completion(server, uri, position, nil).should be_nil
      workspace.definitions(server, uri, position).should be_nil
    end
  end

  it "uses summary-backed lightweight hover on dirty generic receiver chains" do
    source = <<-CRYSTAL
      def demo
        reply_channel = Channel(String).new
        reply_channel.receive.upcase
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      workspace.recalculate_dependencies(server, project)
      result = Crystalline::Analysis.compile(
        server,
        uri,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil
      project.semantic_summary = Crystalline::Lightweight::Summary.from_result(result.not_nil!)

      mark_workspace_document_dirty(workspace.opened_documents[uri.to_s].not_nil!, source)

      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("reply_channel.receive.upcase") }
      character = lines[line_number].rindex("upcase").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      hover = workspace.hover(server, uri, position)
      hover.should_not be_nil
      hover.not_nil!.contents.as(LSP::MarkupContent).value.should contain("String#upcase")
    end
  end

  it "uses current-source lightweight overlays for dirty file method hovers" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo
        greeter = Greeter.new
        greeter.shout
      end
    CRYSTAL

    dirty_source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end

        def whisper : String
          "."
        end
      end

      def demo
        greeter = Greeter.new
        greeter.whisper
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      workspace.recalculate_dependencies(server, project)
      result = Crystalline::Analysis.compile(
        server,
        uri,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil
      project.semantic_summary = Crystalline::Lightweight::Summary.from_result(result.not_nil!)

      mark_workspace_document_dirty(workspace.opened_documents[uri.to_s].not_nil!, dirty_source)

      lines = dirty_source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("greeter.whisper") }
      character = lines[line_number].rindex("whisper").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      hover = workspace.hover(server, uri, position)
      hover.should_not be_nil
      hover.not_nil!.contents.as(LSP::MarkupContent).value.should contain("Greeter#whisper() : String")
    end
  end

  it "uses dirty-buffer hover for relative namespace tuple and try chains" do
    source = <<-CRYSTAL
      module Outer
        class Visitor
          def process : Tuple(Array(String), Hash(String, Tuple(String | Nil, Int32 | Nil)))
            {["hello"], {"key" => {nil, 1}}}
          end
        end

        def self.demo
          nodes, context = Visitor.new.process
          nodes.last?.try do |node|
            node.upcase
          end
        end
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      workspace.recalculate_dependencies(server, project)
      result = Crystalline::Analysis.compile(
        server,
        uri,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil
      project.semantic_summary = Crystalline::Lightweight::Summary.from_result(result.not_nil!)

      mark_workspace_document_dirty(workspace.opened_documents[uri.to_s].not_nil!, source)

      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("node.upcase") }
      character = lines[line_number].rindex("upcase").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      hover = workspace.hover(server, uri, position)
      hover.should_not be_nil
      hover.not_nil!.contents.as(LSP::MarkupContent).value.should contain("String#upcase")
    end
  end

  it "uses dirty-buffer hover through is_a? and conditional-assignment helper chains" do
    source = <<-CRYSTAL
      module Outer
        class Location
          def expanded_location : String
            "x"
          end
        end

        class Item
          def location : Outer::Location | Nil
            Outer::Location.new
          end
        end

        class Node
          def target_defs : Array(Outer::Item) | Nil
            [Outer::Item.new]
          end
        end

        def self.demo(node : Outer::Node | String)
          if node.is_a?(Outer::Node)
            if (defs = node.target_defs)
              defs.compact_map do |d|
                d.location.try do |loc|
                  loc.expanded_location.upcase
                end
              end
            end
          end
        end
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      workspace.recalculate_dependencies(server, project)
      result = Crystalline::Analysis.compile(
        server,
        uri,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil
      project.semantic_summary = Crystalline::Lightweight::Summary.from_result(result.not_nil!)

      mark_workspace_document_dirty(workspace.opened_documents[uri.to_s].not_nil!, source)

      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("loc.expanded_location.upcase") }
      character = lines[line_number].rindex("upcase").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      hover = workspace.hover(server, uri, position)
      hover.should_not be_nil
      hover.not_nil!.contents.as(LSP::MarkupContent).value.should contain("String#upcase")
    end
  end

  it "uses dirty-buffer hover inside exception-handler bodies" do
    source = <<-CRYSTAL
      def demo
        reply_channel = Channel(String).new

        begin
          reply_channel.receive.upcase
        rescue error : Exception
          error.message
        ensure
          1
        end
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      workspace.recalculate_dependencies(server, project)
      result = Crystalline::Analysis.compile(
        server,
        uri,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil
      project.semantic_summary = Crystalline::Lightweight::Summary.from_result(result.not_nil!)

      mark_workspace_document_dirty(workspace.opened_documents[uri.to_s].not_nil!, source)

      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("reply_channel.receive.upcase") }
      character = lines[line_number].rindex("receive").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      hover = workspace.hover(server, uri, position)
      hover.should_not be_nil
      hover.not_nil!.contents.as(LSP::MarkupContent).value.should contain("Channel(String)#receive()")
    end
  end

  it "uses dirty-buffer hover inside assigned begin-style value bodies" do
    source = <<-CRYSTAL
      def demo(items : Array(String))
        value = begin
          items.each do |item|
            item.upcase
          end
        end
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      workspace.recalculate_dependencies(server, project)
      result = Crystalline::Analysis.compile(
        server,
        uri,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil
      project.semantic_summary = Crystalline::Lightweight::Summary.from_result(result.not_nil!)

      mark_workspace_document_dirty(workspace.opened_documents[uri.to_s].not_nil!, source)

      lines = source.lines(chomp: false)
      line_number = lines.index! { |line| line.includes?("item.upcase") }
      character = lines[line_number].rindex("upcase").not_nil! + 2
      position = LSP::Position.new(line: line_number, character: character)

      hover = workspace.hover(server, uri, position)
      hover.should_not be_nil
      hover.not_nil!.contents.as(LSP::MarkupContent).value.should contain("String#upcase")
    end
  end

  it "invalidates the project entry cache on save" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end
    CRYSTAL

    with_workspace_document(source) do |server, workspace, uri|
      project = workspace.projects.first?.not_nil!
      entry_point = project.entry_point?.not_nil!
      result = Crystalline::Analysis.compile(
        server,
        entry_point,
        lib_path: project.default_lib_path,
        ignore_diagnostics: true,
        wants_doc: true,
        compiler_flags: project.flags,
      )
      result.should_not be_nil

      workspace.seed_result_cache(entry_point.to_s, result)
      workspace.result_cache_invalidated?(entry_point.to_s).should be_false

      workspace.save_document(
        server,
        LSP::DidSaveTextDocumentParams.new(
          text_document: LSP::TextDocumentIdentifier.new(uri: uri.to_s),
        ),
      )

      workspace.result_cache_invalidated?(entry_point.to_s).should be_true
    end
  end
end
