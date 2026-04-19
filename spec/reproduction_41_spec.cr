require "spec"
require "../src/crystalline/text_document"
require "lsp/base/range"

describe Crystalline::TextDocument do
  it "fixes #41: does not strip newlines during incremental updates" do
    initial_content = "def foo\nend\n"
    doc = Crystalline::TextDocument.new(URI.parse("file:///test.cr"), nil, initial_content)
    doc.contents.should eq(initial_content)

    # Simulation: Append something at the end of the line (at the newline position)
    # Line 0 is "def foo\n" (length 8)
    # Character 8 is the \n.
    range = LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 8),
      end: LSP::Position.new(line: 0, character: 8)
    )
    # We append a comment right at the newline.
    doc.update_contents([{"# comment", range}], version: 1)

    # Expected behavior without .chomp: "def foo\n# commentend\n"
    # (Actually, character 8 is the start of the newline, so adding "# comment" there
    # should result in "def foo# comment\nend\n")

    # Let's try appending after the newline (char 9 on line 0 doesn't exist, but char 0 on line 1 does)
    # To truly test the .chomp issue:
    # If we edit line 0 at character 8 (the \n itself).
    # prefix = line[...8] -> "def foo\n"
    # If .chomp is used, prefix becomes "def foo"
    # Then we add "# comment"
    # Result: "def foo# commentend\n" (newline is LOST)

    doc.contents.should contain("\n")
    doc.contents.should eq("def foo\n# commentend\n")
  end
end
