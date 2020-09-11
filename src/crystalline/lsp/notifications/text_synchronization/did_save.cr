require "json"
require "../../tools"
require "../../base/*"
require "../notification_message"

module LSP
  # The document save notification is sent from the client to the server when the document was saved in the client.
  class DidSaveNotification < NotificationMessage
    @method = "textDocument/didSave"
    property params : DidSaveTextDocumentParams
  end

  struct DidSaveTextDocumentParams
    include Initializer
    include JSON::Serializable

    # The document that was saved.
    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    # Optional, the content when saved. Depends on the includeText value
    # when the save notification was requested.
    property text : String?
  end
end
