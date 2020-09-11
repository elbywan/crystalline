require "json"
require "../tools"

# An item to transfer a text document from the client to the server.
class LSP::TextDocumentItem
  include JSON::Serializable
  include Initializer

  # The text document's URI.
  property uri : String

  # The text document's language identifier.
  @[JSON::Field(key: "languageId")]
  property language_id : String

  # The version number of this document (it will increase after each
  # change, including undo/redo).
  property version : Int32

  # The content of the opened text document.
  property text : String
end
