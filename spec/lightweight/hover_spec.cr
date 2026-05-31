require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/lightweight/hover"

private def build_lightweight_hover_query(source : String)
  path = File.join(Dir.tempdir, "crystalline-lightweight-hover-#{Random::Secure.hex(8)}.cr")
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

private def build_syntax_hover_query(source : String)
  index = Crystalline::Lightweight::Index.from_source(source)
  raise "expected syntax index" unless index
  Crystalline::Lightweight::Query.new(index)
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

  it "hovers chained receiver methods using explicit return types" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class Factory
        def build : Greeter
          Greeter.new
        end
      end

      def demo
        factory = Factory.new
        factory.build.shout
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.strip == "factory.build.shout" }
    column_number = lines[line_number].rindex("shout").not_nil! + 2

    hover = Crystalline::Lightweight::Hover.hover(source, line_number, column_number, query)
    hover.should_not be_nil
    hover_value(hover.not_nil!).should contain("Greeter#shout() : String")
  end

  it "hovers self and instance variables from lightweight inference" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class Wrapper
        def initialize
          @greeter = Greeter.new
        end

        def hello : String
          "hi"
        end

        def demo
          self
          @greeter
          self.hello
          @greeter.shout
        end
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)

    self_line_number = lines.index! { |item| item.strip == "self" }
    self_column_number = lines[self_line_number].index("self").not_nil! + 1
    self_hover = Crystalline::Lightweight::Hover.hover(source, self_line_number, self_column_number, query)
    self_hover.should_not be_nil
    hover_value(self_hover.not_nil!).should contain("self : Wrapper")

    ivar_line_number = lines.index! { |item| item.strip == "@greeter" }
    ivar_column_number = lines[ivar_line_number].index("@greeter").not_nil! + 2
    ivar_hover = Crystalline::Lightweight::Hover.hover(source, ivar_line_number, ivar_column_number, query)
    ivar_hover.should_not be_nil
    hover_value(ivar_hover.not_nil!).should contain("@greeter : Greeter")

    self_method_line_number = lines.index! { |item| item.strip == "self.hello" }
    self_method_column_number = lines[self_method_line_number].rindex("hello").not_nil! + 2
    self_method_hover = Crystalline::Lightweight::Hover.hover(source, self_method_line_number, self_method_column_number, query)
    self_method_hover.should_not be_nil
    hover_value(self_method_hover.not_nil!).should contain("Wrapper#hello() : String")

    ivar_method_line_number = lines.index! { |item| item.strip == "@greeter.shout" }
    ivar_method_column_number = lines[ivar_method_line_number].rindex("shout").not_nil! + 2
    ivar_method_hover = Crystalline::Lightweight::Hover.hover(source, ivar_method_line_number, ivar_method_column_number, query)
    ivar_method_hover.should_not be_nil
    hover_value(ivar_method_hover.not_nil!).should contain("Greeter#shout() : String")
  end

  it "hovers helper and container receiver methods" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo(candidate : Greeter | Nil)
        items = [Greeter.new]
        items.first.shout
        candidate.not_nil!.shout
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)

    first_line_number = lines.index! { |item| item.strip == "items.first.shout" }
    first_column_number = lines[first_line_number].rindex("shout").not_nil! + 2
    first_hover = Crystalline::Lightweight::Hover.hover(source, first_line_number, first_column_number, query)
    first_hover.should_not be_nil
    hover_value(first_hover.not_nil!).should contain("Greeter#shout() : String")

    not_nil_line_number = lines.index! { |item| item.strip == "candidate.not_nil!.shout" }
    not_nil_column_number = lines[not_nil_line_number].rindex("shout").not_nil! + 2
    not_nil_hover = Crystalline::Lightweight::Hover.hover(source, not_nil_line_number, not_nil_column_number, query)
    not_nil_hover.should_not be_nil
    hover_value(not_nil_hover.not_nil!).should contain("Greeter#shout() : String")
  end

  it "hovers methods in standalone syntax-only files" do
    source = <<-CRYSTAL
      class Clazz
        def method1(num : Int32)
          2
        end
      end

      puts Clazz.new.method1(num: 42)
    CRYSTAL

    query = build_syntax_hover_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.includes?("Clazz.new.method1") }
    column_number = lines[line_number].rindex("method1").not_nil! + 2

    hover = Crystalline::Lightweight::Hover.hover(source, line_number, column_number, query)
    hover.should_not be_nil
    hover_value(hover.not_nil!).should contain("Clazz#method1(num : Int32)")
  end

  it "hovers block arguments inferred from helpers" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo
        items = [Greeter.new]
        items.each_with_index do |item, index|
          item
          index
        end

        Greeter.new.tap do |value|
          value
        end
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)

    item_line_number = lines.index! { |item| item.strip == "item" }
    item_column_number = lines[item_line_number].index("item").not_nil! + 1
    item_hover = Crystalline::Lightweight::Hover.hover(source, item_line_number, item_column_number, query)
    item_hover.should_not be_nil
    hover_value(item_hover.not_nil!).should contain("item : Greeter")

    index_line_number = lines.index! { |item| item.strip == "index" }
    index_column_number = lines[index_line_number].index("index").not_nil! + 1
    index_hover = Crystalline::Lightweight::Hover.hover(source, index_line_number, index_column_number, query)
    index_hover.should_not be_nil
    hover_value(index_hover.not_nil!).should contain("index : Int32")

    value_line_number = lines.index! { |item| item.strip == "value" }
    value_column_number = lines[value_line_number].index("value").not_nil! + 1
    value_hover = Crystalline::Lightweight::Hover.hover(source, value_line_number, value_column_number, query)
    value_hover.should_not be_nil
    hover_value(value_hover.not_nil!).should contain("value : Greeter")
  end

  it "hovers tuple and named tuple derived receivers" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo
        pair = {Greeter.new, 1}
        pair.first.shout

        named = {greeter: Greeter.new}
        named.greeter.shout
      end
    CRYSTAL

    query = build_lightweight_hover_query(source)
    lines = source.lines(chomp: false)

    tuple_line_number = lines.index! { |item| item.strip == "pair.first.shout" }
    tuple_column_number = lines[tuple_line_number].rindex("shout").not_nil! + 2
    tuple_hover = Crystalline::Lightweight::Hover.hover(source, tuple_line_number, tuple_column_number, query)
    tuple_hover.should_not be_nil
    hover_value(tuple_hover.not_nil!).should contain("Greeter#shout() : String")

    named_line_number = lines.index! { |item| item.strip == "named.greeter.shout" }
    named_column_number = lines[named_line_number].rindex("shout").not_nil! + 2
    named_hover = Crystalline::Lightweight::Hover.hover(source, named_line_number, named_column_number, query)
    named_hover.should_not be_nil
    hover_value(named_hover.not_nil!).should contain("Greeter#shout() : String")
  end
end
