require "spec"
require "../src/crystalline/requires"
require "../src/crystalline/main"
require "../src/crystalline/lightweight_query"
require "../src/crystalline/lightweight_inference"

private def build_lightweight_index(source : String)
  path = File.join(Dir.current, ".tmp-crystalline-lightweight-inference-#{Random::Secure.hex(8)}.cr")
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
    Crystalline::Lightweight::Index.from_program(result.program)
  ensure
    File.delete(path) if File.exists?(path)
  end
end

describe Crystalline::Lightweight::Inference do
  it "infers argument restrictions and simple literal assignments before the cursor" do
    index = build_lightweight_index <<-CRYSTAL
      class Foo
      end

      def top_level(value : Bool) : Int32
        value ? 1 : 0
      end
    CRYSTAL

    source = <<-CRYSTAL
      def demo(x : Int32)
        message = "hello"
        enabled = true
        amount = 1
        thing = Foo.new
        total = top_level(enabled)
        amount
      end
    CRYSTAL

    inference = Crystalline::Lightweight::Inference.for(
      source,
      7,
      14,
      Crystalline::Lightweight::Query.new(index),
    )

    inference.should_not be_nil
    inference = inference.not_nil!
    inference.types_for("x").should eq(["Int32"])
    inference.types_for("message").should eq(["String"])
    inference.types_for("enabled").should eq(["Bool"])
    inference.types_for("amount").should eq(["Int32"])
    inference.types_for("thing").should eq(["Foo"])
    inference.types_for("total").should eq(["Int32"])
  end

  it "infers self and instance variables from the enclosing type" do
    index = build_lightweight_index <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end

      class Wrapper
        def hello : String
          "hi"
        end
      end
    CRYSTAL

    source = <<-CRYSTAL
      class Wrapper
        def initialize
          @greeter = Greeter.new
        end

        def demo
          current = self
          @greeter.shout
          current.hello
        end

        def hello : String
          "hi"
        end
      end
    CRYSTAL

    inference = Crystalline::Lightweight::Inference.for(
      source,
      8,
      12,
      Crystalline::Lightweight::Query.new(index),
    )

    inference.should_not be_nil
    inference = inference.not_nil!
    inference.self_types.should eq({["Wrapper"], false})
    inference.types_for("current").should eq(["Wrapper"])
    inference.types_for_instance_var("@greeter").should eq(["Greeter"])
  end
end
