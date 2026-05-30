require "spec"
require "../src/crystalline/requires"
require "../src/crystalline/main"
require "../src/crystalline/lightweight_hover"

private def build_lightweight_hover_query(source : String)
  path = File.join(Dir.current, ".tmp-crystalline-lightweight-hover-#{Random::Secure.hex(8)}.cr")
  File.write(path, source)

  begin
    Crystalline::EnvironmentConfig.run
    server = LSP::Server.new(IO::Memory.new, IO::Memory.new)
    result = Crystalline::Analysis.compile(
      server,
      URI.parse("file://#{path}"),
      lib_path: File.join(Dir.current, "lib"),
      top_level: true,
      ignore_diagnostics: true,
    )
    raise "expected top-level semantic result" unless result
    Crystalline::Lightweight::Query.new(Crystalline::Lightweight::Index.from_program(result.program))
  ensure
    File.delete(path) if File.exists?(path)
  end
end

private def hover_value(hover : LSP::Hover)
  hover.contents.as(LSP::MarkupContent).value
end

describe Crystalline::Lightweight::Hover do
  it "hovers inferred local variable types" do
    source = <<-CRYSTAL
      class Greeter
      end

      def demo
        greeter = Greeter.new
        greeter
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.strip == "greeter" }
    column_number = lines[line_number].index("greeter").not_nil! + 2

    hover = Crystalline::Lightweight::Hover.hover(source, line_number, column_number, query)
    hover.should_not be_nil
    hover_value(hover.not_nil!).should contain("greeter : Greeter")
  end

  it "hovers instance methods from inferred local receivers" do
    source = <<-CRYSTAL
      class Greeter
        def greet(name : String) : String
          name
        end
      end

      def demo
        greeter = Greeter.new
        greeter.greet
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.strip == "greeter.greet" }
    column_number = lines[line_number].rindex("greet").not_nil! + 2

    hover = Crystalline::Lightweight::Hover.hover(source, line_number, column_number, query)
    hover.should_not be_nil
    hover_value(hover.not_nil!).should contain("Greeter#greet(name : String) : String")
  end

  it "hovers class methods from constant receivers" do
    source = <<-CRYSTAL
      class Greeter
        def self.build(name : String) : Greeter
          new
        end
      end

      def demo
        Greeter.build
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.strip == "Greeter.build" }
    column_number = lines[line_number].rindex("build").not_nil! + 2

    hover = Crystalline::Lightweight::Hover.hover(source, line_number, column_number, query)
    hover.should_not be_nil
    hover_value(hover.not_nil!).should contain("Greeter.build(name : String) : Greeter")
  end

  it "hovers type names from the lightweight index" do
    source = <<-CRYSTAL
      # Greeter docs
      class Greeter
      end

      def demo
        Greeter
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.strip == "Greeter" }
    column_number = lines[line_number].index("Greeter").not_nil! + 2

    hover = Crystalline::Lightweight::Hover.hover(source, line_number, column_number, query)
    hover.should_not be_nil
    value = hover_value(hover.not_nil!)
    value.should contain("Greeter")
  end
end
