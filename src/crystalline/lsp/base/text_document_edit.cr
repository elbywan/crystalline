require "json"
require "../tools"
require "./versioned_text_document_identifier"
require "./text_edit"

# Describes textual changes on a single text document.
#
# The text document is referred to as a VersionedTextDocumentIdentifier to allow clients
# to check the text document version before an edit is applied. A TextDocumentEdit
# describes all changes on a version Si and after they are applied move the document
# to version Si+1.
# So the creator of a TextDocumentEdit doesn’t need to sort the array of edits or do
# any kind of ordering.
# However the edits must be non overlapping.
class LSP::TextDocumentEdit
  include JSON::Serializable
  include Initializer

  # The text document to change.
  @[JSON::Field(key: "textDocument")]
  property text_document : VersionedTextDocumentIdentifier

  # The edits to be applied.
  property edits : Array(TextEdit)
end
