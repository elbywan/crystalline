require "json"
require "../../tools"
require "./*"

# ClientCapabilities define capabilities for dynamic registration, workspace and text document features the client supports.
# The experimental can be used to pass experimental capabilities under development.
# For future compatibility a ClientCapabilities object literal can have more properties set than currently defined.
# Servers receiving a ClientCapabilities object literal with unknown properties should ignore these properties.
# A missing property should be interpreted as an absence of the capability.
# If a missing property normally defines sub properties, all missing sub properties should be interpreted as an absence of the corresponding capability.
struct LSP::ClientCapabilities
  include Initializer
  include JSON::Serializable

  struct Workspace
    include Initializer
    include JSON::Serializable

    # The client supports applying batch edits
    # to the workspace by supporting the request
    # 'workspace/applyEdit'
    @[JSON::Field(key: "applyEdit")]
    property apply_edit : Bool?

    # Capabilities specific to `WorkspaceEdit`s
    @[JSON::Field(key: "workspaceEdit")]
    property workspace_edit : WorkspaceEditClientCapabilities?

    # Capabilities specific to the `workspace/didChangeConfiguration` notification.
    @[JSON::Field(key: "didChangeConfiguration")]
    property did_change_configuration : DidChangeConfigurationClientCapabilities?

    # Capabilities specific to the `workspace/didChangeWatchedFiles` notification.
    @[JSON::Field(key: "didChangeWatchedFiles")]
    property did_change_watched_files : DidChangeWatchedFilesClientCapabilities?

    # Capabilities specific to the `workspace/symbol` request.
    property symbol : WorkspaceSymbolClientCapabilities?

    # Capabilities specific to the `workspace/executeCommand` request.
    @[JSON::Field(key: "executeCommand")]
    property execute_command : ExecuteCommandClientCapabilities?

    # The client has support for workspace folders.
    # Since 3.6.0
    @[JSON::Field(key: "workspaceFolders")]
    property workspace_folders : Bool?

    # The client supports `workspace/configuration` requests.
    # Since 3.6.0
    property configuration : Bool?
  end

  # Workspace specific client capabilities.
  property workspace : Workspace?

  # Text document specific client capabilities.
  @[JSON::Field(key: "textDocument")]
  property text_document : TextDocumentClientCapabilities?

  struct Window
    include Initializer
    include JSON::Serializable

    # Whether client supports handling progress notifications. If set servers are allowed to
    # report in `workDoneProgress` property in the request specific server capabilities.
    # Since 3.15.0

    @[JSON::Field(key: "workDoneProgress")]
    property work_done_progress : Bool?
  end

  # Window specific client capabilities.
  property window : Window?

  # Experimental client capabilities.
  property experimental : JSON::Any?

  def ignore_diagnostics? : Bool
    text_document = @text_document
    text_document.nil? || text_document.publish_diagnostics.nil?
  end
end
