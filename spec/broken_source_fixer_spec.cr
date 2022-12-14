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
      call(1) do |x|
    end
    CRYSTAL
    def foo
      call(1) do |x|; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call(1) do |x, y|
    end
    CRYSTAL
    def foo
      call(1) do |x, y|; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call do
    end
    CRYSTAL
    def foo
      call do; end
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

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call(1) { |x|
    end
    CRYSTAL
    def foo
      call(1) { |x|; }
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call(1) { |x, y|
    end
    CRYSTAL
    def foo
      call(1) { |x, y|; }
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call {
    end
    CRYSTAL
    def foo
      call {; }
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      call x {
    end
    CRYSTAL
    def foo
      call x {; }
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    call x {
    CRYSTAL
    call x {; }
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    unless foo
    CRYSTAL
    unless foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    while foo
    CRYSTAL
    while foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    until foo
    CRYSTAL
    until foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      if bar
        1
      else
    end
    CRYSTAL
    def foo
      if bar
        1
      else; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      unless bar
        1
      else
    end
    CRYSTAL
    def foo
      unless bar
        1
      else; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      if bar
        1
      elsif bar
    end
    CRYSTAL
    def foo
      if bar
        1
      elsif bar; end
    end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private def foo
    CRYSTAL
    private def foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    protected def foo
    CRYSTAL
    protected def foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private class Foo
    CRYSTAL
    private class Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private struct Foo
    CRYSTAL
    private struct Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private module Foo
    CRYSTAL
    private module Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private enum Foo
    CRYSTAL
    private enum Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private annotation Foo
    CRYSTAL
    private annotation Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    abstract class Foo
    CRYSTAL
    abstract class Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private abstract class Foo
    CRYSTAL
    private abstract class Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    abstract struct Foo
    CRYSTAL
    abstract struct Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    private abstract struct Foo
    CRYSTAL
    private abstract struct Foo; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo(
    )
      1
    CRYSTAL
    def foo(
    )
      1; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    foo 1,
      bar do
    CRYSTAL
    foo 1,
      bar do; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    begin
      puts 1
    CRYSTAL
    begin
      puts 1; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    begin
      puts 1
    rescue
      puts 2
    CRYSTAL
    begin
      puts 1
    rescue
      puts 2; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    begin
      puts 1
    rescue ex
      puts 2
    CRYSTAL
    begin
      puts 1
    rescue ex
      puts 2; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    begin
      puts 1
    ensure
      puts 2
    CRYSTAL
    begin
      puts 1
    ensure
      puts 2; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    begin
      puts 1
    rescue
      puts 2
    else
      puts 3
    CRYSTAL
    begin
      puts 1
    rescue
      puts 2
    else
      puts 3; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      puts 1
    rescue
      puts 2
    CRYSTAL
    def foo
      puts 1
    rescue
      puts 2; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      puts 1
    rescue
      puts 2
    else
      puts 3
    CRYSTAL
    def foo
      puts 1
    rescue
      puts 2
    else
      puts 3; end
    CRYSTAL

  it_fixes <<-CRYSTAL, <<-CRYSTAL
    def foo
      puts 1
    ensure
      puts 2
    CRYSTAL
    def foo
      puts 1
    ensure
      puts 2; end
    CRYSTAL
end
