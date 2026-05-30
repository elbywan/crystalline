require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/lightweight/query"
require "../../src/crystalline/lightweight/inference"

private def build_lightweight_index(source : String)
  path = File.join(Dir.tempdir, "crystalline-lightweight-inference-#{Random::Secure.hex(8)}.cr")
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

  it "merges conditional branch assignments into union-like local types" do
    index = build_lightweight_index <<-CRYSTAL
      class Foo
      end
    CRYSTAL

    source = <<-CRYSTAL
      def demo(flag : Bool)
        value = 1

        if flag
          item = Foo.new
          value = "hello"
        else
          item = 1
        end

        item
        value
      end
    CRYSTAL

    inference = Crystalline::Lightweight::Inference.for(
      source,
      11,
      8,
      Crystalline::Lightweight::Query.new(index),
    )

    inference.should_not be_nil
    inference = inference.not_nil!
    inference.types_for("item").sort.should eq(["Foo", "Int32"])
    inference.types_for("value").sort.should eq(["Int32", "String"])
  end

  it "expands union restrictions and explicit return types into individual names" do
    index = build_lightweight_index <<-CRYSTAL
      class Foo
      end

      class Bar
      end

      def maybe_item : Foo | Bar | Nil
        Foo.new
      end
    CRYSTAL

    source = <<-CRYSTAL
      def demo(value : Foo | Bar | Nil)
        result = maybe_item
        result
      end
    CRYSTAL

    inference = Crystalline::Lightweight::Inference.for(
      source,
      3,
      8,
      Crystalline::Lightweight::Query.new(index),
    )

    inference.should_not be_nil
    inference = inference.not_nil!
    inference.types_for("value").sort.should eq(["Bar", "Foo", "Nil"])
    inference.types_for("result").sort.should eq(["Bar", "Foo", "Nil"])
  end

  it "narrows types inside is_a? and truthy conditional branches" do
    index = build_lightweight_index <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end
    CRYSTAL

    isa_source = <<-CRYSTAL
      def demo(candidate : Greeter | Nil | Int32)
        if candidate.is_a?(Greeter)
          narrowed = candidate
          narrowed
        end
      end
    CRYSTAL

    narrowed_inference = Crystalline::Lightweight::Inference.for(
      isa_source,
      4,
      10,
      Crystalline::Lightweight::Query.new(index),
    )

    narrowed_inference.should_not be_nil
    narrowed_inference = narrowed_inference.not_nil!
    narrowed_inference.types_for("candidate").should eq(["Greeter"])
    narrowed_inference.types_for("narrowed").should eq(["Greeter"])

    truthy_source = <<-CRYSTAL
      def demo(candidate : Greeter | Nil)
        if candidate
          truthy_candidate = candidate
          truthy_candidate
        end
      end
    CRYSTAL

    truthy_inference = Crystalline::Lightweight::Inference.for(
      truthy_source,
      4,
      12,
      Crystalline::Lightweight::Query.new(index),
    )

    truthy_inference.should_not be_nil
    truthy_inference = truthy_inference.not_nil!
    truthy_inference.types_for("candidate").should eq(["Greeter"])
    truthy_inference.types_for("truthy_candidate").should eq(["Greeter"])
  end

  it "infers fallback types from logical or expressions" do
    index = build_lightweight_index <<-CRYSTAL
      class Greeter
        def shout : String
          "!"
        end
      end
    CRYSTAL

    source = <<-CRYSTAL
      def demo(candidate : Greeter | Nil)
        resolved = candidate || Greeter.new
        resolved
      end
    CRYSTAL

    inference = Crystalline::Lightweight::Inference.for(
      source,
      3,
      12,
      Crystalline::Lightweight::Query.new(index),
    )

    inference.should_not be_nil
    inference = inference.not_nil!
    inference.types_for("resolved").should eq(["Greeter"])
  end
end
