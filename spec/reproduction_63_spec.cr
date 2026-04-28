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
  it "fixes #63: range formatting does not add extra newlines" do
    server = FakeServer.new
    workspace = Crystalline::Workspace.new(server, "file:///tmp")

    file_uri = URI.parse("file:///tmp/test_paste.cr")
    initial_content = "foo \"bar\"\n"

    workspace.open_document(LSP::DidOpenTextDocumentParams.new(
      text_document: LSP::TextDocumentItem.new(
        uri: file_uri.to_s,
        language_id: "crystal",
        version: 1,
        text: initial_content
      )
    ))

    # Range is the whole first line except the newline.
    range = LSP::Range.new(
      start: LSP::Position.new(line: 0, character: 0),
      end: LSP::Position.new(line: 0, character: 9)
    )

    params = LSP::DocumentRangeFormattingParams.new(
      text_document: LSP::TextDocumentIdentifier.new(uri: file_uri.to_s),
      range: range,
      options: LSP::FormattingOptions.new(tab_size: 2, insert_spaces: true)
    )

    result = workspace.format_document(params)
    result.should_not be_nil
    if result
      formatted_text, _ = result
      # Crystal.format("foo \"bar\"") normally returns "foo \"bar\"\n"
      # Our fix should chomp it.
      formatted_text.should eq("foo \"bar\"")
    end
  end
end
