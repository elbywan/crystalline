require "spec"
require "lsp/server"
require "lsp/notifications/text_synchronization/did_change"
require "lsp/notifications/text_synchronization/did_open"
require "lsp/requests/language_features/formatting"
require "lsp/requests/language_features/range_formatting"
require "../src/crystalline/requires"
require "../src/crystalline/*"

class FakeServer < LSP::Server
  @client_capabilities = LSP::ClientCapabilities.new

  def initialize
    super(IO::Memory.new, IO::Memory.new)
  end

  def client_capabilities : LSP::ClientCapabilities
    @client_capabilities
  end
end

describe Crystalline::Workspace do
  it "reproduces #63: range formatting does not add extra newlines" do
    server = FakeServer.new
    workspace = Crystalline::Workspace.new(server, "file://#{Dir.current}")

    file_uri = URI.parse("file://#{Dir.current}/test_paste.cr")
    initial_content = "foo \"bar\"\n"

    workspace.open_document(LSP::DidOpenTextDocumentParams.new(
      text_document: LSP::TextDocumentItem.new(
        uri: file_uri.to_s,
        language_id: "crystal",
        version: 1,
        text: initial_content
      )
    ))

    # Let's simulate the range formatting request.
    range = LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 5),
      end: LSP::Position.new(line: 0, character: 9)
    )

    params = LSP::DocumentRangeFormattingParams.new(
      text_document: LSP::TextDocumentIdentifier.new(uri: file_uri.to_s),
      range: range,
      options: LSP::FormattingOptions.new(tab_size: 2, insert_spaces: true)
    )

    # Update the document to reflect the paste
    workspace.update_document(server, LSP::DidChangeTextDocumentParams.new(
      text_document: LSP::VersionedTextDocumentIdentifier.new(uri: file_uri.to_s, version: 2),
      content_changes: [
        LSP::DidChangeTextDocumentParams::TextDocumentContentChangeEvent.new(
          range: LSP::Range.new(
            start: LSP::Position.new(line: 0, character: 5),
            end: LSP::Position.new(line: 0, character: 5)
          ),
          text: "text"
        ),
      ]
    ))

    result = workspace.format_document(params)
    result.should_not be_nil
    formatted_text, _ = result.not_nil!

    formatted_text.should eq("text")
  end
end
