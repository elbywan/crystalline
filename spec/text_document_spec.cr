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

  it "clamps out of range update columns to the line content" do
    document = doc("abc\ndef\n")

    document.update_contents([
      {"X", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 3),
        end: LSP::Position.new(line: 0, character: 999),
      )},
    ], version: 1)

    document.contents.should eq("abcX\ndef\n")
  end

  it "clamps an out of range end column when replacing across lines" do
    document = doc("abc\ndef\n")

    document.update_contents([
      {"Z", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 1),
        end: LSP::Position.new(line: 1, character: 999),
      )},
    ], version: 1)

    document.contents.should eq("aZ\n")
  end

  it "counts update columns as UTF-16 code units after an astral character" do
    document = doc("a😀b\n")

    document.update_contents([
      {"!", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 3),
        end: LSP::Position.new(line: 0, character: 4),
      )},
    ], version: 1)

    document.contents.should eq("a😀!\n")
  end

  it "counts update columns as UTF-16 code units when replacing an astral character" do
    document = doc("a😀b\n")

    document.update_contents([
      {"?", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 1),
        end: LSP::Position.new(line: 0, character: 3),
      )},
    ], version: 1)

    document.contents.should eq("a?b\n")
  end

  it "keeps carriage returns out of the updated line content" do
    document = doc("abc\r\ndef\r\n")

    # End of line 0, where an LSP position stops before the terminator.
    document.update_contents([
      {"X", LSP::Range.new(
        start: LSP::Position.new(line: 0, character: 3),
        end: LSP::Position.new(line: 0, character: 3),
      )},
    ], version: 1)

    document.contents.should eq("abcX\r\ndef\r\n")

    # Replacing the whole of line 1 must keep its own terminator.
    document.update_contents([
      {"Z", LSP::Range.new(
        start: LSP::Position.new(line: 1, character: 0),
        end: LSP::Position.new(line: 1, character: 3),
      )},
    ], version: 2)

    document.contents.should eq("abcX\r\nZ\r\n")
  end

  it "updates the version on full document updates" do
    document = doc("foo\n")

    document.update_contents([
      {"bar\n", nil},
    ], version: 7)

    document.contents.should eq("bar\n")
    document.version.should eq(7)
  end

  it "applies queued changes in order once the missing version arrives" do
    document = doc("one\ntwo\nthree\n")

    document.update_contents([{"ONE", LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 0),
      end: LSP::Position.new(line: 0, character: 3),
    )}], version: 1)

    # Version 2 is missing: both version 3 changes are queued.
    document.update_contents([{"TWO", LSP::Range.new(
      start: LSP::Position.new(line: 1, character: 0),
      end: LSP::Position.new(line: 1, character: 3),
    )}], version: 3)
    document.update_contents([{"THREE", LSP::Range.new(
      start: LSP::Position.new(line: 2, character: 0),
      end: LSP::Position.new(line: 2, character: 5),
    )}], version: 3)

    document.update_contents([{"two", LSP::Range.new(
      start: LSP::Position.new(line: 1, character: 0),
      end: LSP::Position.new(line: 1, character: 3),
    )}], version: 2)

    document.contents.should eq("ONE\nTWO\nTHREE\n")
  end

  it "keeps changes queued while a version is still missing" do
    document = doc("first\n")

    document.update_contents([{"SECND", LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 0),
      end: LSP::Position.new(line: 0, character: 5),
    )}], version: 1)
    document.update_contents([{"FORTH", LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 0),
      end: LSP::Position.new(line: 0, character: 5),
    )}], version: 4)

    document.update_contents([{"THIRD", LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 0),
      end: LSP::Position.new(line: 0, character: 5),
    )}], version: 2)

    # Version 3 is still missing: the version 4 change must stay queued.
    document.contents.should eq("THIRD\n")

    document.update_contents([{"FOURT", LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 0),
      end: LSP::Position.new(line: 0, character: 5),
    )}], version: 3)

    # The gap is filled: the queued version 4 change now applies.
    document.contents.should eq("FORTH\n")
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
