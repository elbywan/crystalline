require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/completion_context"
require "../../src/crystalline/lightweight/completion"

private def build_lightweight_query(source : String)
  path = File.join(Dir.tempdir, "crystalline-lightweight-completion-#{Random::Secure.hex(8)}.cr")
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

private def build_syntax_query(source : String)
  index = Crystalline::Lightweight::Index.from_source(source)
  raise "expected syntax index" unless index
  Crystalline::Lightweight::Query.new(index)
end

describe Crystalline::Lightweight::Completion do
  it "completes instance methods from inferred local receiver types" do
    source = <<-CRYSTAL
      class Greeter
        def greet(name : String) : String
          name
        end

        def shout : String
          "!"
        end
      end

      def demo
        greeter = Greeter.new
        greeter.gr
      end
    CRYSTAL

    query = build_lightweight_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.includes?("greeter.gr") }
    line = lines[line_number]
    context = Crystalline::CompletionContext.detect(line, line.size - 1, nil)
    context.should_not be_nil

    items = Crystalline::Lightweight::Completion.complete(
      source,
      line_number,
      context.not_nil!,
      query,
    )

    items.should_not be_nil
    items = items.not_nil!
    items.map(&.insert_text).compact.should contain("greet")
    items.map(&.insert_text).compact.should contain("shout")
  end

  it "completes class methods from constant receivers" do
    source = <<-CRYSTAL
      class Greeter
        def self.build(name : String) : Greeter
          new
        end
      end

      def demo
        Greeter.bu
      end
    CRYSTAL

    query = build_lightweight_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.includes?("Greeter.bu") }
    line = lines[line_number]
    context = Crystalline::CompletionContext.detect(line, line.size - 1, nil)
    context.should_not be_nil

    items = Crystalline::Lightweight::Completion.complete(
      source,
      line_number,
      context.not_nil!,
      query,
    )

    items.should_not be_nil
    items = items.not_nil!
    items.map(&.insert_text).compact.should contain("build")
  end

  it "completes chained receivers using explicit return types" do
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
        factory.build.sh
      end
    CRYSTAL

    query = build_lightweight_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.includes?("factory.build.sh") }
    line = lines[line_number]
    context = Crystalline::CompletionContext.detect(line, line.size - 1, nil)
    context.should_not be_nil

    items = Crystalline::Lightweight::Completion.complete(
      source,
      line_number,
      context.not_nil!,
      query,
    )

    items.should_not be_nil
    items = items.not_nil!
    items.map(&.insert_text).compact.should contain("shout")
  end

  it "completes self and instance variable receivers" do
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
          self.he
          @greeter.sh
        end
      end
    CRYSTAL

    query = build_lightweight_query(source)
    lines = source.lines(chomp: false)

    self_line_number = lines.index! { |item| item.includes?("self.he") }
    self_context = Crystalline::CompletionContext.detect(lines[self_line_number], lines[self_line_number].size - 1, nil)
    self_context.should_not be_nil

    self_items = Crystalline::Lightweight::Completion.complete(
      source,
      self_line_number,
      self_context.not_nil!,
      query,
    )

    self_items.should_not be_nil
    self_items.not_nil!.map(&.insert_text).compact.should contain("hello")

    ivar_line_number = lines.index! { |item| item.includes?("@greeter.sh") }
    ivar_context = Crystalline::CompletionContext.detect(lines[ivar_line_number], lines[ivar_line_number].size - 1, nil)
    ivar_context.should_not be_nil

    ivar_items = Crystalline::Lightweight::Completion.complete(
      source,
      ivar_line_number,
      ivar_context.not_nil!,
      query,
    )

    ivar_items.should_not be_nil
    ivar_items.not_nil!.map(&.insert_text).compact.should contain("shout")
  end

  it "completes locals, top-level methods, self, instance variables, and types without dot triggers" do
    source = <<-CRYSTAL
      class Greeter
      end

      def top_level_name : String
        "name"
      end

      class Wrapper
        def initialize
          @greeter = Greeter.new
        end

        def demo(local_name : String)
          local_copy = local_name
          loc
          top_lev
          sel
          @gre
          Gre
        end
      end
    CRYSTAL

    query = build_lightweight_query(source)
    lines = source.lines(chomp: false)

    local_line_number = lines.index! { |item| item.strip == "loc" }
    local_context = Crystalline::CompletionContext.detect(lines[local_line_number], lines[local_line_number].index("loc").not_nil! + 3, nil)
    local_items = Crystalline::Lightweight::Completion.complete(source, local_line_number, local_context.not_nil!, query).not_nil!
    local_items.map(&.insert_text).compact.should contain("local_copy")

    method_line_number = lines.index! { |item| item.strip == "top_lev" }
    method_context = Crystalline::CompletionContext.detect(lines[method_line_number], lines[method_line_number].index("top_lev").not_nil! + 7, nil)
    method_items = Crystalline::Lightweight::Completion.complete(source, method_line_number, method_context.not_nil!, query).not_nil!
    method_items.map(&.insert_text).compact.should contain("top_level_name")

    self_line_number = lines.index! { |item| item.strip == "sel" }
    self_context = Crystalline::CompletionContext.detect(lines[self_line_number], lines[self_line_number].index("sel").not_nil! + 3, nil)
    self_items = Crystalline::Lightweight::Completion.complete(source, self_line_number, self_context.not_nil!, query).not_nil!
    self_items.map(&.insert_text).compact.should contain("self")

    ivar_line_number = lines.index! { |item| item.strip == "@gre" }
    ivar_context = Crystalline::CompletionContext.detect(lines[ivar_line_number], lines[ivar_line_number].index("@gre").not_nil! + 4, nil)
    ivar_items = Crystalline::Lightweight::Completion.complete(source, ivar_line_number, ivar_context.not_nil!, query).not_nil!
    ivar_items.map(&.insert_text).compact.should contain("greeter")

    type_line_number = lines.index! { |item| item.strip == "Gre" }
    type_context = Crystalline::CompletionContext.detect(lines[type_line_number], lines[type_line_number].index("Gre").not_nil! + 3, nil)
    type_items = Crystalline::Lightweight::Completion.complete(source, type_line_number, type_context.not_nil!, query).not_nil!
    type_items.map(&.insert_text).compact.should contain("Greeter")
  end

  it "completes narrowed receivers inside conditional branches" do
    isa_source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo(candidate : Greeter | Nil | Int32)
        if candidate.is_a?(Greeter)
          candidate.sh
        end
      end
    CRYSTAL

    query = build_lightweight_query(isa_source)
    isa_lines = isa_source.lines(chomp: false)
    isa_line_number = isa_lines.index! { |item| item.includes?("candidate.sh") }
    isa_context = Crystalline::CompletionContext.detect(isa_lines[isa_line_number], isa_lines[isa_line_number].size - 1, nil)
    isa_items = Crystalline::Lightweight::Completion.complete(isa_source, isa_line_number, isa_context.not_nil!, query).not_nil!
    isa_items.map(&.insert_text).compact.should contain("shout")

    truthy_source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo(candidate : Greeter | Nil)
        if candidate
          candidate.sh
        end
      end
    CRYSTAL

    truthy_query = build_lightweight_query(truthy_source)
    truthy_lines = truthy_source.lines(chomp: false)
    truthy_line_number = truthy_lines.index! { |item| item.includes?("candidate.sh") }
    truthy_context = Crystalline::CompletionContext.detect(truthy_lines[truthy_line_number], truthy_lines[truthy_line_number].size - 1, nil)
    truthy_items = Crystalline::Lightweight::Completion.complete(truthy_source, truthy_line_number, truthy_context.not_nil!, truthy_query).not_nil!
    truthy_items.map(&.insert_text).compact.should contain("shout")
  end

  it "completes receivers inferred from logical or fallbacks" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo(candidate : Greeter | Nil)
        resolved = candidate || Greeter.new
        resolved.sh
      end
    CRYSTAL

    query = build_lightweight_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.includes?("resolved.sh") }
    context = Crystalline::CompletionContext.detect(lines[line_number], lines[line_number].size - 1, nil)
    items = Crystalline::Lightweight::Completion.complete(source, line_number, context.not_nil!, query).not_nil!
    items.map(&.insert_text).compact.should contain("shout")
  end

  it "completes common helper and container receivers" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      def demo(candidate : Greeter | Nil)
        items = [Greeter.new]
        items.first.sh
        candidate.not_nil!.sh
      end
    CRYSTAL

    query = build_lightweight_query(source)
    lines = source.lines(chomp: false)

    first_line_number = lines.index! { |item| item.includes?("items.first.sh") }
    first_context = Crystalline::CompletionContext.detect(lines[first_line_number], lines[first_line_number].size - 1, nil)
    first_items = Crystalline::Lightweight::Completion.complete(source, first_line_number, first_context.not_nil!, query).not_nil!
    first_items.map(&.insert_text).compact.should contain("shout")

    not_nil_line_number = lines.index! { |item| item.includes?("candidate.not_nil!.sh") }
    not_nil_context = Crystalline::CompletionContext.detect(lines[not_nil_line_number], lines[not_nil_line_number].size - 1, nil)
    not_nil_items = Crystalline::Lightweight::Completion.complete(source, not_nil_line_number, not_nil_context.not_nil!, query).not_nil!
    not_nil_items.map(&.insert_text).compact.should contain("shout")
  end

  it "completes methods in standalone syntax-only files" do
    source = <<-CRYSTAL
      class Clazz
        def method1(num : Int32)
          2
        end
      end

      puts Clazz.new.method
    CRYSTAL

    query = build_syntax_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |item| item.includes?("Clazz.new.method") }
    context = Crystalline::CompletionContext.detect(lines[line_number], lines[line_number].size - 1, nil)
    items = Crystalline::Lightweight::Completion.complete(source, line_number, context.not_nil!, query).not_nil!
    items.map(&.insert_text).compact.should contain("method1")
  end
end
