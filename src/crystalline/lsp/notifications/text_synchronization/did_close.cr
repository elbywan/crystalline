require "json"
require "../../tools"
require "../../base/*"
require "../notification_message"

module LSP
  # The document close notification is sent from the client to the server when the document got closed in the client.
  # The document’s master now exists where the document’s Uri points to (e.g. if the document’s Uri is a file Uri the master now exists on disk).
  # As with the open notification the close notification is about managing the document’s content.
  # Receiving a close notification doesn’t mean that the document was open in an editor before.
  # A close notification requires a previous open notification to be sent.
  # Note that a server’s ability to fulfill requests is independent of whether a text document is open or closed.
  class DidCloseNotification < NotificationMessage
    @method = "textDocument/didClose"
    property params : DidCloseTextDocumentParams
  end

  struct DidCloseTextDocumentParams
    include Initializer
    include JSON::Serializable

    # The document that was closed.
    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
  end
end
