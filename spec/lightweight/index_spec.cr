require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/lightweight/query"

private def build_lightweight_index(source : String)
  path = File.join(Dir.tempdir, "crystalline-lightweight-index-#{Random::Secure.hex(8)}.cr")
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

describe Crystalline::Lightweight::Index do
  it "provides query helpers over the lightweight index" do
    index = build_lightweight_index <<-CRYSTAL
      module Foo
        class Bar
          def baz(x : Int32) : String
            x.to_s
          end

          def self.make(name : String) : Foo::Bar
            new
          end
        end
      end

      def top_level(value : Bool) : Int32
        value ? 1 : 0
      end
    CRYSTAL

    query = Crystalline::Lightweight::Query.new(index)

    query.find_type("Foo::Bar").should_not be_nil
    query.subtypes_for("Foo").should contain("Foo::Bar")

    instance_methods = query.methods_for("Foo::Bar")
    instance_methods.map(&.name).should contain("baz")
    instance_methods.any?(&.macro).should be_false

    class_methods = query.methods_for("Foo::Bar", class_method: true)
    class_methods.map(&.name).should contain("make")

    query.top_level_methods.map(&.name).should contain("top_level")
  end

  it "indexes top-level methods and nested types from top-level semantic results" do
    index = build_lightweight_index <<-CRYSTAL
      module Foo
        class Bar
          def baz(x : Int32) : String
            x.to_s
          end

          def self.make(name : String) : Foo::Bar
            new
          end
        end
      end

      def top_level(value : Bool) : Int32
        value ? 1 : 0
      end
    CRYSTAL

    foo = index.types["Foo"]?
    foo.should_not be_nil
    foo.not_nil!.kind.should eq(Crystalline::Lightweight::TypeKind::Module)
    foo.not_nil!.subtypes.should contain("Foo::Bar")

    bar = index.types["Foo::Bar"]?
    bar.should_not be_nil
    bar = bar.not_nil!
    bar.kind.should eq(Crystalline::Lightweight::TypeKind::Class)

    baz = bar.methods.find { |method| method.name == "baz" && !method.class_method && !method.macro }
    baz.should_not be_nil
    baz = baz.not_nil!
    baz.return_type.should eq("String")
    baz.args.map(&.restriction).should eq(["Int32"])

    make = bar.methods.find { |method| method.name == "make" && method.class_method }
    make.should_not be_nil
    make = make.not_nil!
    make.return_type.should eq("Foo::Bar")
    make.args.map(&.restriction).should eq(["String"])

    top_level = index.top_level_methods.find(&.name.==("top_level"))
    top_level.should_not be_nil
    top_level.not_nil!.return_type.should eq("Int32")
    top_level.not_nil!.args.map(&.restriction).should eq(["Bool"])
  end
end
