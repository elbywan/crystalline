require "json"
require "../../tools"
require "../../ext/enum"

module LSP
  # The kind of resource operations supported by the client.
  Enum.string ResourceOperationKind do
    # Supports creating new files and folders.
    Create
    # Supports renaming existing files and folders.
    Rename
    # Supports deleting existing files and folders.
    Delete
  end

  Enum.string FailureHandlingKind do
    # Applying the workspace change is simply aborted if one of the changes provided
    # fails. All operations executed before the failing operation stay executed.
    Abort
    # All operations are executed transactional. That means they either all
    # succeed or no changes at all are applied to the workspace.
    Transactional
    # If the workspace edit contains only textual file changes they are executed transactional.
    # If resource changes (create, rename or delete file) are part of the change the failure
    # handling strategy is abort.
    TextOnlyTransactional
    # The client tries to undo the operations already executed. But there is no
    # guarantee that this is succeeding.
    Undo
  end

  class WorkspaceEditClientCapabilities
    include Initializer
    include JSON::Serializable

    # The client supports versioned document changes in `WorkspaceEdit`s
    @[JSON::Field(key: "documentChanges")]
    property document_changes : Bool?
    # The resource operations the client supports. Clients should at least
    # support 'create', 'rename' and 'delete' files and folders.
    @[JSON::Field(key: "resourceOperations")]
    property resource_operations : Array(ResourceOperationKind)?

    # The failure handling strategy of a client if applying the workspace edit
    # fails.
    @[JSON::Field(key: "failureHandling")]
    property failure_handling : FailureHandlingKind?
  end

  class WorkspaceFoldersServerCapabilities
    include Initializer
    include JSON::Serializable

    # The server has support for workspace folders
    property supported : Bool?

    # Whether the server wants to receive workspace folder
    # change notifications.
    #
    # If a string is provided, the string is treated as an ID
    # under which the notification is registered on the client
    # side. The ID can be used to unregister for these events
    # using the `client/unregisterCapability` request.
    @[JSON::Field(key: "changeNotifications")]
    property change_notifications : (String | Bool)?
  end
end
