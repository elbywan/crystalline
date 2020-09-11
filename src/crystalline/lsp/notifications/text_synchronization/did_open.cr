require "json"
require "../../tools"
require "../../base/*"
require "../notification_message"

module LSP
  # The document open notification is sent from the client to the server to signal newly opened text documents.
  # The document’s content is now managed by the client and the server must not try to read the document’s content using the document’s Uri.
  # Open in this sense means it is managed by the client. It doesn’t necessarily mean that its content is presented in an editor.
  # An open notification must not be sent more than once without a corresponding close notification send before.
  # This means open and close notification must be balanced and the max open count for a particular textDocument is one.
  # Note that a server’s ability to fulfill requests is independent of whether a text document is open or closed.
  class DidOpenNotification < NotificationMessage
    @method = "textDocument/didOpen"
    property params : DidOpenTextDocumentParams
  end

  struct DidOpenTextDocumentParams
    include Initializer
    include JSON::Serializable

    # The document that was opened.
    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentItem
  end
end
