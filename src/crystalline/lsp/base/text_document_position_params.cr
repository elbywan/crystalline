require "json"
require "../tools"
require "./text_document_identifier"
require "./position"

module LSP::TextDocumentPositionParams
  include JSON::Serializable
  include Initializer

  # The text document.
  @[JSON::Field(key: "textDocument")]
  property text_document : TextDocumentIdentifier
  # The position inside the text document.
  property position : Position
end
