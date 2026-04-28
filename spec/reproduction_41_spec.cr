require "spec"
require "../src/crystalline/text_document"
require "lsp/base/range"

describe Crystalline::TextDocument do
  it "fixes #41: does not strip newlines during incremental updates" do
    initial_content = "def foo\nend\n"
    doc = Crystalline::TextDocument.new(URI.parse("file:///test.cr"), nil, initial_content)
    doc.contents.should eq(initial_content)

    # Simulation: Append a comment at the end of the line (at the newline position)
    # Line 0 is "def foo\n" (length 8)
    # Character 8 is the \n.
    range = LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 8),
      end: LSP::Position.new(line: 0, character: 8)
    )

    # If .chomp was used, prefix would be "def foo" (stripping \n).
    # Adding "# comment" would result in "def foo# commentend\n" (LOST newline).
    # WITHOUT .chomp, prefix is "def foo\n".
    # Result should be "def foo\n# commentend\n"

    doc.update_contents([{"# comment", range}], version: 2)
    doc.contents.should eq("def foo\n# commentend\n")
  end
end
