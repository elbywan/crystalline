require "spec"
require "file_utils"
require "lsp/server"
require "../../src/crystalline/lightweight/workspace_symbol"

private def with_project_source(source : String, *, suffix = "", &)
  root = File.join(Dir.tempdir, "crystalline-workspace-symbol-#{Random::Secure.hex(8)}#{suffix}")
  path = File.join(root, "src", "app.cr")
  Dir.mkdir_p(File.dirname(path))
  File.write(path, source)
  begin
    yield root, path
  ensure
    FileUtils.rm_rf(root)
  end
end

private def spans(range : LSP::Range)
  {range.start.line, range.start.character, range.end.line, range.end.character}
end

private def symbols_for(root : String, path : String, query : String)
  index = Crystalline::Lightweight::Index.from_source(File.read(path), path).not_nil!
  Crystalline::Lightweight::WorkspaceSymbol.symbols(index, root, query)
end

describe Crystalline::Lightweight::WorkspaceSymbol do
  it "lists matching types and methods with their kind and name range" do
    source = <<-CR
    module Services
      class Worker
        def initialize(@name : String)
        end

        def run
        end
      end
    end
    CR

    with_project_source(source) do |root, path|
      symbols = symbols_for(root, path, "work")
      symbols.map { |symbol| {symbol.name, symbol.kind.value, symbol.container_name} }.should eq([
        {"Worker", LSP::SymbolKind::Class.value, "Services"},
      ])

      symbol = symbols.first
      spans(symbol.location.range).should eq({1, 8, 1, 14})
      symbol.location.uri.should end_with("src/app.cr")
    end
  end

  it "ranks prefix matches before substring matches" do
    source = <<-CR
    class Network
    end

    class Worker
    end
    CR

    with_project_source(source) do |root, path|
      symbols_for(root, path, "wor").map(&.name).should eq(["Worker", "Network"])
    end
  end

  it "lists methods and top level functions" do
    source = <<-CR
    def helper
    end

    class Worker
      def initialize
      end

      def perform
      end
    end
    CR

    with_project_source(source) do |root, path|
      symbols = symbols_for(root, path, "er")
      symbols.map { |symbol| {symbol.name, symbol.kind.value} }.should eq([
        {"Worker", LSP::SymbolKind::Class.value},
        {"helper", LSP::SymbolKind::Function.value},
        {"perform", LSP::SymbolKind::Method.value},
      ])
    end
  end

  it "leaves out files outside of the project and its dependencies" do
    source = <<-CR
    class ProjectWorker
    end
    CR

    with_project_source(source) do |root, path|
      index = Crystalline::Lightweight::Index.from_source(File.read(path), path).not_nil!
      index.types["DependencyWorker"] = Crystalline::Lightweight::TypeInfo.new(
        "DependencyWorker", Crystalline::Lightweight::TypeKind::Class,
        nil,
        Crystal::Location.new(File.join(root, "lib", "shard", "src", "dep.cr"), line_number: 1, column_number: 7),
        Crystal::Location.new(File.join(root, "lib", "shard", "src", "dep.cr"), line_number: 1, column_number: 7),
      )
      index.types["StandardWorker"] = Crystalline::Lightweight::TypeInfo.new(
        "StandardWorker", Crystalline::Lightweight::TypeKind::Class,
        nil,
        Crystal::Location.new("/usr/lib/crystal/worker.cr", line_number: 1, column_number: 7),
        Crystal::Location.new("/usr/lib/crystal/worker.cr", line_number: 1, column_number: 7),
      )

      symbols = Crystalline::Lightweight::WorkspaceSymbol.symbols(index, root, "worker")

      symbols.map(&.name).should eq(["ProjectWorker"])
    end
  end

  it "escapes the file URI of the symbols" do
    with_project_source("class SpacedWorker\nend\n", suffix: " with space") do |root, path|
      uri = symbols_for(root, path, "spaced").first.location.uri

      uri.starts_with?("file://").should be_true
      uri.includes?("%20").should be_true
    end
  end

  it "leaves out files of a sibling directory sharing the root prefix" do
    with_project_source("class RootWorker\nend\n") do |root, path|
      index = Crystalline::Lightweight::Index.from_source("class SiblingWorker\nend\n", "#{root}-sibling/src/app.cr").not_nil!
      index.types["RootWorker"] = Crystalline::Lightweight::Index.from_source(File.read(path), path).not_nil!.types["RootWorker"]

      Crystalline::Lightweight::WorkspaceSymbol.symbols(index, root, "worker").map(&.name).should eq(["RootWorker"])
    end
  end

  it "returns nothing when no symbol matches" do
    with_project_source("class Worker\nend\n") do |root, path|
      symbols_for(root, path, "nothing").should be_empty
    end
  end
end
