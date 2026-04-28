require "spec"
require "lsp/server"
require "../src/crystalline/requires"
require "../src/crystalline/*"

class FakeServer < LSP::Server
  def initialize
    super(IO::Memory.new, IO::Memory.new)
    @client_capabilities = LSP::ClientCapabilities.new
  end
end

describe Crystalline::Workspace do
  it "fixes #76: does not trigger completion inside comments" do
    server = FakeServer.new
    workspace = Crystalline::Workspace.new(server, "file:///tmp")

    file_uri = URI.parse("file:///tmp/test_comment.cr")
    # A file with a dot inside a comment
    content = <<-CRYSTAL
    # This is a comment.
    puts 1
    CRYSTAL

    workspace.open_document(LSP::DidOpenTextDocumentParams.new(
      text_document: LSP::TextDocumentItem.new(
        uri: file_uri.to_s,
        language_id: "crystal",
        version: 1,
        text: content
      )
    ))

    # Try to trigger completion at the dot in the comment
    # Line 0, character 19 (the dot at the end of "comment.")
    pos = LSP::Position.new(line: 0, character: 19)

    result = workspace.completion(server, file_uri, pos, ".")

    # It should return nil early because it's in a comment.
    result.should be_nil

    # Test case: # inside a string should NOT be a comment
    content_with_string = <<-CRYSTAL
    x = "this is # not a comment."
    CRYSTAL
    workspace.update_document(server, LSP::DidChangeTextDocumentParams.new(
      text_document: LSP::VersionedTextDocumentIdentifier.new(uri: file_uri.to_s, version: 2),
      content_changes: [
        LSP::DidChangeTextDocumentParams::TextDocumentContentChangeEvent.new(
          text: content_with_string
        ),
      ]
    ))
    # Dot at end of string. Line 0, character 31.
    pos_in_string = LSP::Position.new(line: 0, character: 31)
    workspace.completion(server, file_uri, pos_in_string, ".")
  end
end
