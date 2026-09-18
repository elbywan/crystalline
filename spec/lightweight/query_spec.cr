require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/lightweight/query"

private def index_from_source(source : String) : Crystalline::Lightweight::Index
  Crystalline::Lightweight::Index.from_source(source).should_not be_nil
end

private def build_lightweight_index(source : String)
  path = File.join(Dir.tempdir, "crystalline-lightweight-query-#{Random::Secure.hex(8)}.cr")
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

describe Crystalline::Lightweight::Query do
  it "overlays a dirty-buffer index on top of the base index" do
    base = index_from_source(<<-CRYSTAL)
      class Greeter
        def hello : Int32
          1
        end

        def old_method : Int32
          1
        end
      end

      def top_level_old : Int32
        1
      end

      def top_level_shared : String
        "base"
      end
    CRYSTAL

    # The leading comment shifts every location by one line, so the
    # redefined methods live at different locations than the base ones.
    overlay = index_from_source(<<-CRYSTAL)
      # overlay

      class Greeter
        def hello : String
          "hi"
        end

        def new_method : Bool
          true
        end
      end

      def top_level_new : Float64
        1.0
      end

      def top_level_shared : String
        "overlay"
      end
    CRYSTAL

    query = Crystalline::Lightweight::Query.new(base, overlay: overlay)

    # A same-signature redefinition at a different location wins.
    hello = query.methods_for("Greeter").find(&.name.==("hello")).should_not be_nil
    hello.not_nil!.return_type.should eq("String")

    # Base methods that are not redefined are preserved, and overlay-only
    # methods are added.
    query.methods_for("Greeter").map(&.name).should contain("old_method")
    query.methods_for("Greeter").map(&.name).should contain("new_method")

    # A type defined only in the overlay resolves.
    query.find_type("Greeter").should_not be_nil

    # Top-level methods: the overlay adds new ones, same-signature base wins.
    query.top_level_methods.map(&.name).should contain("top_level_new")
    query.top_level_methods.map(&.name).should contain("top_level_old")
    shared = query.top_level_methods.find(&.name.==("top_level_shared")).should_not be_nil
    shared.not_nil!.return_type.should eq("String")
  end

  it "keeps the base method when the overlay redefinition shares its location" do
    source = <<-CRYSTAL
      class Greeter
        def hello : Int32
          1
        end
      end
    CRYSTAL

    base = index_from_source(source)
    overlay = index_from_source(source.gsub(": Int32", ": String"))

    query = Crystalline::Lightweight::Query.new(base, overlay: overlay)
    hello = query.methods_for("Greeter").find(&.name.==("hello")).should_not be_nil
    hello.not_nil!.return_type.should eq("Int32")
  end

  it "resolves types and methods from the secondary index" do
    base = index_from_source("class Base\nend\n")
    secondary = index_from_source("class Side\n  def side_method : Int32\n    1\n  end\nend\n")

    query = Crystalline::Lightweight::Query.new(base, secondary: secondary)
    query.find_type("Side").should_not be_nil
    query.methods_for("Side").map(&.name).should contain("side_method")
    query.resolve_type_name("Side").should eq("Side")
  end

  it "resolves methods through overlay-redefined parent types" do
    # Parent/child relationships are only recorded by the compiled program
    # index, so the base index comes from a top-level semantic pass.
    base = build_lightweight_index(<<-CRYSTAL)
      class Parent
        def base_method : Int32
          1
        end
      end

      class Child < Parent
      end
    CRYSTAL

    # The leading comment shifts every location by one line, so the
    # redefined parent methods live at different locations than the base.
    overlay = index_from_source(<<-CRYSTAL)
      # overlay

      class Parent
        def overlay_method : String
          "o"
        end
      end
    CRYSTAL

    query = Crystalline::Lightweight::Query.new(base, overlay: overlay)
    names = query.methods_for("Child").map(&.name)
    names.should contain("base_method")
    names.should contain("overlay_method")
  end
end

describe "splat arguments through specialization" do
  it "keeps splat, double splat and block arguments when specializing a generic method" do
    index = Crystalline::Lightweight::Index.from_source(<<-SRC, "/tmp/specialize_spec.cr").not_nil!
    class Box(T)
      def fill(*values : T, **options, &block : T -> Nil)
      end
    end
    SRC
    query = Crystalline::Lightweight::Query.new(index)

    method = query.methods_for("Box(Int32)").find { |candidate| candidate.name == "fill" }.not_nil!

    method.args.map(&.splat).should eq([true])
    method.double_splat.not_nil!.name.should eq("options")
    method.block_arg.not_nil!.name.should eq("block")
  end
end
