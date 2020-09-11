require "json"
require "../tools"
require "./text_edit"
require "./text_document_edit"
require "./file_resource_changes"

module LSP
  # A workspace edit represents changes to many resources managed in the workspace.
  #
  # The edit should either provide changes or documentChanges.
  # If the client can handle versioned document edits and if documentChanges are present, the latter are preferred over changes.
  class WorkspaceEdit
    include Initializer
    include JSON::Serializable

    # Holds changes to existing resources.
    property changes : Hash(String, Array(TextEdit))

    # Depending on the client capability `workspace.workspaceEdit.resourceOperations` document changes
    # are either an array of `TextDocumentEdit`s to express changes to n different text documents
    # where each text document edit addresses a specific version of a text document. Or it can contain
    # above `TextDocumentEdit`s mixed with create, rename and delete file / folder operations.
    #
    # Whether a client supports versioned document edits is expressed via
    # `workspace.workspaceEdit.documentChanges` client capability.
    #
    # If a client neither supports `documentChanges` nor `workspace.workspaceEdit.resourceOperations` then
    # only plain `TextEdit`s using the `changes` property are supported.
    @[JSON::Field(key: "documentChanges")]
    property document_changes : (Array(TextDocumentEdit) | Array(TextDocumentEdit | CreateFile | RenameFile | DeleteFile))?
  end
end
