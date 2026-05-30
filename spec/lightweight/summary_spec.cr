require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/completion_context"
require "../../src/crystalline/lightweight/completion"
require "../../src/crystalline/lightweight/summary"

private def build_query_with_summary(source : String)
  path = File.join(Dir.tempdir, "crystalline-lightweight-summary-#{Random::Secure.hex(8)}.cr")
  File.write(path, source)

  begin
    Crystalline::EnvironmentConfig.run
    server = LSP::Server.new(IO::Memory.new, IO::Memory.new)

    top_level_result = Crystalline::Analysis.compile(
      server,
      URI.parse("file://#{path}"),
      lib_path: File.join(Dir.current, "lib"),
      top_level: true,
      ignore_diagnostics: true,
    )
    raise "expected top-level semantic result" unless top_level_result

    semantic_result = Crystalline::Analysis.compile(
      server,
      URI.parse("file://#{path}"),
      lib_path: File.join(Dir.current, "lib"),
      ignore_diagnostics: true,
      wants_doc: true,
    )
    raise "expected semantic result" unless semantic_result

    index = Crystalline::Lightweight::Index.from_program(top_level_result.program)
    summary = Crystalline::Lightweight::Summary.from_result(semantic_result)
    Crystalline::Lightweight::Query.new(index, summary)
  ensure
    File.delete(path) if File.exists?(path)
  end
end

describe Crystalline::Lightweight::Summary do
  it "captures inferred return types for typed defs" do
    query = build_query_with_summary <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class Factory
        def build
          Greeter.new
        end
      end

      Factory.new.build
    CRYSTAL

    build_method = query.methods_for("Factory").find(&.name.==("build"))
    build_method.should_not be_nil
    build_method.not_nil!.return_type.should eq("Greeter")
  end

  it "uses semantic summaries to resolve ivar types and inferred receiver chains" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class Wrapper
        def seed
          @greeter = Greeter.new
        end

        def build
          @greeter
        end
      end

      wrapper = Wrapper.new
      wrapper.seed
      wrapper.build
    CRYSTAL

    query = build_query_with_summary(source)
    query.instance_var_types_for("Wrapper", "@greeter").sort.should eq(["Greeter", "Nil"])

    completion_source = source + <<-CRYSTAL

      def demo(wrapper : Wrapper)
        wrapper.build.sh
      end
    CRYSTAL

    lines = completion_source.lines(chomp: false)
    line_number = lines.index! { |line| line.includes?("wrapper.build.sh") }
    context = Crystalline::CompletionContext.detect(lines[line_number], lines[line_number].size - 1, nil)
    context.should_not be_nil

    items = Crystalline::Lightweight::Completion.complete(completion_source, line_number, context.not_nil!, query)
    items.should_not be_nil
    items.not_nil!.map(&.insert_text).compact.should contain("shout")
  end
end
