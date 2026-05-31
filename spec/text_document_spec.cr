require "spec"
require "lsp/server"
require "../src/crystalline/text_document"

private def doc(contents : String)
  Crystalline::TextDocument.new(URI.parse("file:///tmp/test.cr"), nil, contents)
end

describe Crystalline::TextDocument do
  it "computes EOF position for empty contents" do
    document = doc("")

    document.eof_position.line.should eq(0)
    document.eof_position.character.should eq(0)
  end

  it "computes EOF position for contents ending with a newline" do
    document = doc("foo\nbar\n")

    document.eof_position.line.should eq(2)
    document.eof_position.character.should eq(0)
  end

  it "computes EOF position for contents without a trailing newline" do
    document = doc("foo\nbar")

    document.eof_position.line.should eq(1)
    document.eof_position.character.should eq(3)
  end

  it "preserves the exact line prefix during partial updates" do
    document = doc("foo\nbar\n")

    document.update_contents([
      {"", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 4),
        end: LSP::Position.new(line: 1, character: 0),
      )},
    ], version: 1)

    document.contents.should eq("foo\nbar\n")
  end

  it "updates the version on full document updates" do
    document = doc("foo\n")

    document.update_contents([
      {"bar\n", nil},
    ], version: 7)

    document.contents.should eq("bar\n")
    document.version.should eq(7)
  end

  it "clears stale pending changes when a full update arrives" do
    document = doc("foo\n")

    document.update_contents([
      {"bar\n", nil},
    ], version: 1)

    document.update_contents([
      {"baz", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 0),
        end: LSP::Position.new(line: 0, character: 3),
      )},
    ], version: 3)

    document.update_contents([
      {"qux\n", nil},
    ], version: 4)

    document.update_contents([
      {"zap", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 0),
        end: LSP::Position.new(line: 0, character: 3),
      )},
    ], version: 5)

    document.contents.should eq("zap\n")
    document.version.should eq(5)
  end

  it "tracks dirty state across edits and saves" do
    document = doc("foo\n")

    document.dirty?.should be_false

    document.update_contents([
      {"bar", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 0),
        end: LSP::Position.new(line: 0, character: 3),
      )},
    ], version: 1)

    document.dirty?.should be_true

    document.mark_saved

    document.dirty?.should be_false
  end
end
