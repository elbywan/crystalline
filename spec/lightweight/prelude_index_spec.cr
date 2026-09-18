require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/lightweight/prelude_index"

describe Crystalline::Lightweight::PreludeIndex do
  it "round-trips the prelude index through the cache format" do
    original = Crystalline::Lightweight::PreludeIndex.generate
    original.should_not be_nil
    original = original.not_nil!
    original.types.size.should be > 500
    original.types["String"]?.should_not be_nil

    path = File.join(Dir.tempdir, "crystalline-prelude-test-#{Random::Secure.hex(8)}.bin")
    begin
      Crystalline::Lightweight::PreludeIndex.save_to_cache_for_test(original, path)
      loaded = Crystalline::Lightweight::PreludeIndex.load_from_cache_for_test(path)
      loaded.should_not be_nil
      loaded = loaded.not_nil!

      loaded.types.size.should eq(original.types.size)
      loaded.top_level_methods.size.should eq(original.top_level_methods.size)

      string_type = loaded.types["String"].should_not be_nil
      string_type.methods.map(&.name).should contain("upcase")
      string_type.methods.map(&.name).should contain("split")
      string_type.parent_types.should contain("Reference")

      # Restrictions and return types survive the round trip.
      to_i = string_type.methods.find(&.name.==("to_i"))
      to_i.should_not be_nil
      to_i.not_nil!.args.first.name.should eq("base")
      to_i.not_nil!.args.first.restriction.should eq("Int")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "indexes aliases with the aliased type as their parent" do
    index = Crystalline::Lightweight::PreludeIndex.generate
    index.should_not be_nil
    index = index.not_nil!

    mutex = index.types["Mutex"]?
    mutex.should_not be_nil
    mutex.not_nil!.kind.should eq(Crystalline::Lightweight::TypeKind::Alias)
    mutex.not_nil!.parent_types.should contain("Sync::Mutex")
  end
end

describe "Crystalline::Lightweight::PreludeIndex cache" do
  it "round trips splat, double splat and block arguments" do
    index = Crystalline::Lightweight::Index.new
    type = Crystalline::Lightweight::TypeInfo.new("CacheProbe", Crystalline::Lightweight::TypeKind::Class)
    type.methods << Crystalline::Lightweight::MethodInfo.new(
      name: "each_entry",
      owner: "CacheProbe",
      args: [
        Crystalline::Lightweight::ArgInfo.new(name: "name", restriction: "String"),
        Crystalline::Lightweight::ArgInfo.new(name: "values", restriction: "Int32", splat: true),
      ],
      return_type: "Nil",
      double_splat: Crystalline::Lightweight::ArgInfo.new(name: "options", restriction: "String"),
      block_arg: Crystalline::Lightweight::ArgInfo.new(name: "block", restriction: "Int32"),
    )
    index.types["CacheProbe"] = type
    index.top_level_methods << Crystalline::Lightweight::MethodInfo.new(
      name: "top_level_probe",
      owner: "::",
      args: [] of Crystalline::Lightweight::ArgInfo,
      return_type: nil,
      double_splat: Crystalline::Lightweight::ArgInfo.new(name: "kwargs", restriction: nil),
      block_arg: Crystalline::Lightweight::ArgInfo.new(name: "block", restriction: nil),
    )

    path = File.join(Dir.tempdir, "crystalline-prelude-cache-#{Random::Secure.hex(8)}.bin")
    begin
      Crystalline::Lightweight::PreludeIndex.save_to_cache_for_test(index, path)
      loaded = Crystalline::Lightweight::PreludeIndex.load_from_cache_for_test(path).not_nil!

      method = loaded.types["CacheProbe"].methods.first
      method.args.map { |arg| {arg.name, arg.splat} }.should eq([{"name", false}, {"values", true}])
      method.double_splat.not_nil!.name.should eq("options")
      method.double_splat.not_nil!.restriction.should eq("String")
      method.block_arg.not_nil!.name.should eq("block")

      top_level = loaded.top_level_methods.first
      top_level.double_splat.not_nil!.name.should eq("kwargs")
      top_level.double_splat.not_nil!.restriction.should be_nil
      top_level.block_arg.not_nil!.name.should eq("block")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
