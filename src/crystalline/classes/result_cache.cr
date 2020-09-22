require "compiler/crystal/**"

module Crystalline
  class ResultCache
    @@reference_clock = Time.monotonic
    @cache : Hash(String, {Crystal::Compiler::Result?, Time::Span?}) = Hash(String, {Crystal::Compiler::Result?, Time::Span?}).new

    def invalidate(entry : String)
      @cache[entry] = { nil, monotonic_now }
    end

    def exists?(entry : String)
      @cache.has_key?(entry)
    end

    def invalidated?(entry : String, *, since : Time::Span? = nil) : Bool
      return false unless exists?(entry)
      invalidation_time = @cache[entry][1]
      if since
        !invalidation_time || invalidation_time.not_nil! > since
      else
        !invalidation_time.nil?
      end
    end

    def get(entry : String)
      @cache[entry]?.try &.[0]
    end

    def set(entry : String, result : Crystal::Compiler::Result?, *, unless_invalidated_since : Time::Span? = nil)
      invalidated = unless_invalidated_since && invalidated?(entry, since: unless_invalidated_since)
      @cache[entry] = { result, nil } unless invalidated
    end

    def monotonic_now
      Time.monotonic - @@reference_clock
    end
  end
end
