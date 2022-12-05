require "spec"
require "../src/crystalline/broken_source_fixer"

def it_fixes(from, to, file = __FILE__, line = __LINE__)
  it(file: file, line: line) do
    Crystalline::BrokenSourceFixer.fix(from).should eq(to)
  end
end

describe Crystalline::BrokenSourceFixer do
  it_fixes <<-CRYSTAL, <<-CRYSTAL
    if foo
    CRYSTAL
    if foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      if bar
    end
    CRYSTAL
    def foo
      if bar; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      if bar

      puts 1
    end
    CRYSTAL
    def foo
      if bar
      end
      puts 1
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      if bar
        if baz

      puts 1
    end
    CRYSTAL
    def foo
      if bar
        if baz
        end; end
      puts 1
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    class Foo
      def bar
      end
    CRYSTAL
    class Foo
      def bar
      end; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    module Foo
      def bar
      end
    CRYSTAL
    module Foo
      def bar
      end; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    struct Foo
      def bar
      end
    CRYSTAL
    struct Foo
      def bar
      end; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    enum Foo
      def bar
      end
    CRYSTAL
    enum Foo
      def bar
      end; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    class Foo
      annotation Bar
    end
    CRYSTAL
    class Foo
      annotation Bar; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    class Foo
      def bar
    end
    CRYSTAL
    class Foo
      def bar; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call(1) do
    end
    CRYSTAL
    def foo
      call(1) do; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call(1) {
    end
    CRYSTAL
    def foo
      call(1) {; }
    end
    CRYSTAL
end
