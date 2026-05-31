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
  it "derives method contracts from available method summaries" do
    query = build_query_with_summary <<-CRYSTAL
      class Greeter
      end

      class Wrapper
        def tap
          self
        end

        def current
          Greeter.new
        end

        def current?
          Greeter.new || nil
        end
      end

      wrapper = Wrapper.new
      wrapper.tap
      wrapper.current
      wrapper.current?
    CRYSTAL

    tap_contracts = query.method_contracts_for("Wrapper", "tap")
    tap_contracts.map(&.kind).should contain(Crystalline::Lightweight::MethodContractKind::YieldSelf)
    tap_contracts.map(&.kind).should contain(Crystalline::Lightweight::MethodContractKind::PreserveReceiver)

    current_contracts = query.method_contracts_for("Wrapper", "current")
    current_contracts.map(&.kind).should contain(Crystalline::Lightweight::MethodContractKind::ReturnValue)

    current_nilable_contracts = query.method_contracts_for("Wrapper", "current?")
    current_nilable_contracts.map(&.kind).should contain(Crystalline::Lightweight::MethodContractKind::ReturnValueOrNil)
  end

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

  it "specializes inherited splat generic owners for tuple receivers" do
    query = build_query_with_summary <<-CRYSTAL
      def demo
        tuple_pair = {1, "x"}
        tuple_pair.each_with_object([] of String) do |item, memo|
          memo << item.to_s
        end
      end
    CRYSTAL

    each_with_object_method = query.methods_for("Tuple(Int32, String)").find(&.name.==("each_with_object"))
    each_with_object_method.should_not be_nil
    each_with_object_method.not_nil!.owner.should eq("Enumerable(Int32 | String)")
  end

  it "uses semantic summaries for tuple destructuring and try block inference" do
    source = <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class CursorVisitor
        def process
          { [Greeter.new], nil }
        end
      end

      CursorVisitor.new.process
    CRYSTAL

    query = build_query_with_summary(source)

    completion_source = source + <<-CRYSTAL

      def demo
        nodes, context = CursorVisitor.new.process
        nodes.last?.try { |node| node.sh }
      end
    CRYSTAL

    lines = completion_source.lines(chomp: false)
    line_number = lines.index! { |line| line.includes?("node.sh") }
    cursor = lines[line_number].index("node.sh").not_nil! + "node.sh".size
    context = Crystalline::CompletionContext.detect(lines[line_number], cursor, nil)
    context.should_not be_nil

    items = Crystalline::Lightweight::Completion.complete(completion_source, line_number, context.not_nil!, query)
    items.should_not be_nil
    items.not_nil!.map(&.insert_text).compact.should contain("shout")
  end
end
