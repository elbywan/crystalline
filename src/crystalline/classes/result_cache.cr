require "compiler/crystal/**"

module Crystalline
  class ResultCache
    # A monotonic timestamp used to store the invalidation date.
    @@reference_clock = Time.monotonic
    # A cache of compiler results with invalidation time, indexed by file name.
    @cache : Hash(String, {Crystal::Compiler::Result?, Time::Span?}) = Hash(String, {Crystal::Compiler::Result?, Time::Span?}).new

    # Remove the result, store the timestamp.
    def invalidate(entry : String)
      @cache[entry] = {nil, monotonic_now}
    end

    # True if the entry (filename) has already been used as a compilation target.
    def exists?(entry : String)
      @cache.has_key?(entry)
    end

    # True if the cache has been invalidated *since* the *since* time argument,
    # or if the entry is invalided if *since* is not provided.
    def invalidated?(entry : String, *, since : Time::Span? = nil) : Bool
      return false unless exists?(entry)
      invalidation_time = @cache[entry][1]
      if since
        !invalidation_time || invalidation_time.not_nil! > since
      else
        !invalidation_time.nil?
      end
    end

    # Get a cache value.
    def get(entry : String)
      @cache[entry]?.try &.[0]
    end

    # Store a compiler result by target name.
    #
    # If *unless_invalidated_since* is provided, is will not store the result if the previous result has been
    # invalidated since the privided timestamp.
    def set(entry : String, result : Crystal::Compiler::Result?, *, unless_invalidated_since : Time::Span? = nil)
      invalidated = unless_invalidated_since && invalidated?(entry, since: unless_invalidated_since)
      @cache[entry] = {result, nil} unless invalidated
    end

    # Return the current monotonic time.
    def monotonic_now
      Time.monotonic - @@reference_clock
    end
  end
end
