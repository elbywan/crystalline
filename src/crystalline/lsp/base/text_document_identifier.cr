require "json"
require "../tools"

# Text documents are identified using a URI. On the protocol level, URIs are passed as strings.
class LSP::TextDocumentIdentifier
  include Initializer
  include JSON::Serializable

  # The text document's URI.
  property uri : String
end
