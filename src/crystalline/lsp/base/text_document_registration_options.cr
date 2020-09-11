require "json"
require "../tools"
require "./document_filter"

# Options to dynamically register for requests for a set of text documents.
module LSP::TextDocumentRegistrationOptions
  # A document selector to identify the scope of the registration. If set to null
  # the document selector provided on the client side will be used.
  @[JSON::Field(key: "documentSelector")]
  property document_selector : DocumentSelector?
end
