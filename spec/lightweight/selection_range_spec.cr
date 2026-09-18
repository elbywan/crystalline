require "spec"
require "../../src/crystalline/lightweight/selection_range"

private def selection_chains(source : String, positions : Array(Tuple(Int32, Int32))) : Array(LSP::SelectionRange)
  lines = source.lines(chomp: false)
  lsp_positions = positions.map { |(line, character)| LSP::Position.new(line: line, character: character) }
  Crystalline::Lightweight::SelectionRange.ranges(source, lsp_positions, lines)
end

# The chain as `{start.line, start.character, end.line, end.character}`
# tuples, innermost first (walking the parents outwards).
private def chain_tuples(chain : LSP::SelectionRange) : Array(Tuple(Int32, Int32, Int32, Int32))
  tuples = [] of Tuple(Int32, Int32, Int32, Int32)
  node : LSP::SelectionRange? = chain
  while node
    range = node.range
    tuples << {range.start.line, range.start.character, range.end.line, range.end.character}
    node = node.parent
  end
  tuples
end

private def chain_contains?(outer : LSP::Range, inner : LSP::Range) : Bool
  {outer.start.line, outer.start.character} <= {inner.start.line, inner.start.character} &&
    {inner.end.line, inner.end.character} <= {outer.end.line, outer.end.character}
end

private def assert_chain_nested(chain : LSP::SelectionRange) : Nil
  child = chain
  while parent = child.parent
    chain_contains?(parent.range, child.range).should be_true
    child = parent
  end
end

describe Crystalline::Lightweight::SelectionRange do
  it "returns the chain of a nested call inside a def, innermost first" do
    source = "def foo\n  bar(baz(1))\nend\n"

    chain = selection_chains(source, [{1, 10}]).first

    chain_tuples(chain).should eq([
      {1, 10, 1, 11}, # `1`
      {1, 6, 1, 12},  # `baz(1)`
      {1, 2, 1, 13},  # `bar(baz(1))`
      {0, 0, 2, 3},   # the def
      {0, 0, 2, 3},   # the document
    ])
  end

  it "contains every child range in its parent for a multiline heredoc" do
    source = "def greet\n  message = <<-TEXT\n    hello\n    TEXT\nend\n"

    chain = selection_chains(source, [{2, 4}]).first
    assert_chain_nested(chain)

    ranges = chain_tuples(chain)
    ranges.should eq([
      {1, 12, 3, 8}, # the heredoc literal, spanning three lines
      {1, 12, 3, 8},
      {1, 2, 3, 8}, # the assignment
      {0, 0, 4, 3}, # the def
      {0, 0, 4, 3}, # the document
    ])
    ranges.first[2].should be > ranges.first[0]
  end

  it "contains every child range in its parent for a multiline call" do
    source = "foo(\n  1,\n  2\n)\n"

    chain = selection_chains(source, [{1, 2}]).first
    assert_chain_nested(chain)

    ranges = chain_tuples(chain)
    ranges.should eq([
      {1, 2, 1, 3}, # `1`
      {0, 0, 3, 1}, # the `foo(...)` call, spanning four lines
      {0, 0, 3, 1}, # the document
    ])
    ranges[1][2].should be > ranges[1][0]
  end

  it "returns one chain per requested position, in order" do
    source = "x = 1\ny = 2\n"

    chains = selection_chains(source, [{0, 4}, {1, 4}])

    chains.size.should eq(2)
    chain_tuples(chains[0]).should eq([
      {0, 4, 0, 5},
      {0, 0, 0, 5},
      {0, 0, 1, 5},
      {0, 0, 1, 5},
    ])
    chain_tuples(chains[1]).should eq([
      {1, 4, 1, 5},
      {1, 0, 1, 5},
      {0, 0, 1, 5},
      {0, 0, 1, 5},
    ])
  end

  it "answers a valid chain for a buffer with a syntax error" do
    source = "def foo(\n"

    chains = selection_chains(source, [{0, 4}])
    chains.size.should eq(1)

    chain = chains.first
    assert_chain_nested(chain)
    chain_tuples(chain).should eq([
      {0, 4, 0, 7}, # `foo`
      {0, 0, 0, 8},
      {0, 0, 0, 8},
    ])
  end

  it "answers from the line and document ranges when no token is under the cursor" do
    source = "def foo(\n  "

    chain_tuples(selection_chains(source, [{1, 2}]).first).should eq([
      {1, 0, 1, 2},
      {0, 0, 1, 2},
    ])
  end

  it "keeps a position past the end of a line inside the document" do
    source = "x = 1\ny = 2\n"

    chain = selection_chains(source, [{0, 20}]).first
    assert_chain_nested(chain)

    ranges = chain_tuples(chain)
    ranges.last.should eq({0, 0, 1, 5})
    ranges.each do |(start_line, _, end_line, end_character)|
      start_line.should be <= 1
      end_line.should be <= 1
      end_character.should be <= 5
    end
  end

  it "converts the requested UTF-16 columns to character columns" do
    source = %(s = "🎉x"\n)

    # The closing quote sits at character index 7, at UTF-16 column 8.
    chain = selection_chains(source, [{0, 8}]).first

    chain_tuples(chain).should eq([
      {0, 4, 0, 9}, # the whole `"🎉x"` literal
      {0, 0, 0, 9},
      {0, 0, 0, 9},
      {0, 0, 0, 9},
    ])
  end

  it "falls back to the token under the cursor inside a comment" do
    source = "# hello\n"

    chain_tuples(selection_chains(source, [{0, 4}]).first).should eq([
      {0, 2, 0, 7}, # `hello`
      {0, 0, 0, 7},
      {0, 0, 0, 7},
    ])
  end

  it "answers a single document range for an empty document" do
    chain_tuples(selection_chains("", [{0, 0}]).first).should eq([{0, 0, 0, 0}])
  end
end
