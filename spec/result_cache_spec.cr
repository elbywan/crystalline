require "spec"
require "../src/crystalline/requires"
require "../src/crystalline/result_cache"

private def compiled_result
  Crystal::Compiler::Result.new(Crystal::Program.new, Crystal::Nop.new)
end

describe Crystalline::ResultCache do
  it "reports an entry holding a result as valid" do
    cache = Crystalline::ResultCache.new
    cache.set("a.cr", nil)

    cache.invalidated?("a.cr").should be_false
  end

  it "compares the invalidation time to the given timestamp" do
    cache = Crystalline::ResultCache.new
    since = cache.monotonic_now
    cache.invalidate("a.cr")

    cache.invalidated?("a.cr").should be_true
    cache.invalidated?("a.cr", since: since).should be_true
    cache.invalidated?("a.cr", since: cache.monotonic_now).should be_false
  end

  it "stores a result compiled after the last invalidation" do
    cache = Crystalline::ResultCache.new
    cache.set("a.cr", nil)
    started = cache.monotonic_now

    cache.set("a.cr", compiled_result, unless_invalidated_since: started)

    cache.get("a.cr").should_not be_nil
  end

  it "discards a result invalidated while the compilation was running" do
    cache = Crystalline::ResultCache.new
    started = cache.monotonic_now
    cache.invalidate("a.cr")

    cache.set("a.cr", compiled_result, unless_invalidated_since: started)

    cache.get("a.cr").should be_nil
    cache.invalidated?("a.cr").should be_true
  end
end
