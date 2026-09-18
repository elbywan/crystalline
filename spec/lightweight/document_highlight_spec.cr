require "spec"
require "lsp/server"
require "../../src/crystalline/lightweight/document_highlight"

private def highlight_spans(source : String, line : Int32, character : Int32) : Array({Int32, Int32, Int32, Int32?})?
  highlights = Crystalline::Lightweight::DocumentHighlight.highlights(source, line, character)
  highlights.try &.map do |highlight|
    {
      highlight.range.start.line,
      highlight.range.start.character,
      highlight.range.end.character,
      highlight.kind.try(&.value),
    }
  end
end

describe Crystalline::Lightweight::DocumentHighlight do
  it "classifies the writes and reads of a local variable" do
    source = "def f\n  count = 1\n  count += 2\n  puts count\n  count, other = 3, 4\nend\n"

    highlight_spans(source, 1, 3).should eq([
      {1, 2, 7, 3},
      {2, 2, 7, 3},
      {3, 7, 12, 2},
      {4, 2, 7, 3},
    ])
  end

  it "does not highlight a shadowing block argument" do
    source = "def f\n  total = 1\n  [1].each { |total| puts total }\n  total\nend\n"

    highlight_spans(source, 1, 3).should eq([
      {1, 2, 7, 3},
      {3, 2, 7, 2},
    ])
  end

  it "highlights outer variables written inside blocks and procs" do
    source = "def f\n  total = 0\n  [1, 2].each { |value| total += value }\n  accumulator = ->{ total }\n  accumulator.call\nend\n"

    highlight_spans(source, 1, 3).should eq([
      {1, 2, 7, 3},   # the write
      {2, 24, 29, 3}, # `total += value` inside the block writes the same variable
      {3, 20, 25, 2}, # the read inside the proc literal
    ])
  end

  it "does not confuse scopes that share a line" do
    # The block argument shadows `x` inside the block, but the cursor sits on
    # the def level assignment: line based containment would pick the block.
    source = "def f; x = 1; [1].each { |x| puts x }; end\n"

    highlight_spans(source, 0, 8).should eq([{0, 7, 8, 3}])
  end

  it "does not highlight same-named locals of other scopes" do
    source = "def f\n  count = 1\n  count\nend\n\ndef g\n  count = 2\n  count\nend\n"

    highlight_spans(source, 2, 3).should eq([
      {1, 2, 7, 3},
      {2, 2, 7, 2},
    ])
  end

  it "highlights parameters and block arguments" do
    source = "def f(count : Int32)\n  count\nend\n"

    highlight_spans(source, 0, 7).should eq([
      {0, 6, 11, 3},
      {1, 2, 7, 2},
    ])
  end

  it "returns nothing for symbols without an exact reference set" do
    source = <<-CR
    class Worker
      getter name : String

      def run
        Worker.new.run
      end
    end
    CR

    # A type name, an instance variable, a method call and a token in a
    # comment cannot be resolved without a full compilation.
    Crystalline::Lightweight::DocumentHighlight.highlights(source, 0, 7).should be_nil
    Crystalline::Lightweight::DocumentHighlight.highlights(source, 4, 8).should be_nil
    Crystalline::Lightweight::DocumentHighlight.highlights(source, 4, 17).should be_nil
  end
end
