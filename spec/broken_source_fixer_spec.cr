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
end
