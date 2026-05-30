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

end
