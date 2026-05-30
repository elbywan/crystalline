require "spec"
require "../src/crystalline/requires"
require "../src/crystalline/main"
require "../src/crystalline/completion_context"
require "../src/crystalline/lightweight_completion"

private def build_lightweight_query(source : String)
  path = File.join(Dir.current, ".tmp-crystalline-lightweight-completion-#{Random::Secure.hex(8)}.cr")
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
end
