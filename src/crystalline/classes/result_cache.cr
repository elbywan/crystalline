require "compiler/crystal/**"

module Crystalline
  class ResultCache
    @cache : Hash(String, Crystal::Compiler::Result) = Hash(String, Crystal::Compiler::Result).new

    def invalidate(entry : String)
      @cache.delete entry
    end

    def get(entry : String)
      @cache[entry]?
    end

    def set(entry : String, result : Crystal::Compiler::Result)
      @cache[entry] = result
    end
  end
end
