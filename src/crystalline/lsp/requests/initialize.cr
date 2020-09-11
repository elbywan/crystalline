require "../base/**"
require "./request_message"
require "../base/capabilities/client_capabilities"

module LSP
  macro finished
    # The initialize request is sent as the first request from the client to the server.
    class InitializeRequest < RequestMessage(InitializeResult)
      @method = "initialize"
      property params : InitializeParams
    end
  end

  class InitializeParams
    include WorkDoneProgressParams
    include Initializer
    include JSON::Serializable

    # The process Id of the parent process that started
    # the server. Is null if the process has not been started by another process.
    # If the parent process is not alive then the server should exit (see exit notification) its process.
    @[JSON::Field(key: "processId")]
    property process_id : Int64 | Int32 | Nil

    # Information about the client.
    @[JSON::Field(key: "clientInfo")]
    property client_info : NamedTuple(
      # The name of the client as defined by the client.
      name: String,
      # The client's version as defined by the client.
      version: String?)?

    # The rootPath of the workspace. Is null
    # if no folder is open.
    @[Deprecated("Use `#root_uri` instead")]
    @[JSON::Field(key: "rootPath")]
    property root_path : String?

    # The rootUri of the workspace. Is null if no
    # folder is open. If both `root_path` and `root_uri` are set
    # `root_uri` wins.
    @[JSON::Field(key: "rootUri")]
    property root_uri : String?

    # User provided initialization options.
    @[JSON::Field(key: "initializationOptions")]
    property initialization_options : JSON::Any?

    # The capabilities provided by the client (editor or tool).
    property capabilities : ClientCapabilities
    # The initial trace setting. If omitted trace is disabled ('off').
    property trace : String?

    # The workspace folders configured in the client when the server starts.
    # This property is only available if the client supports workspace folders.
    # It can be `null` if the client supports workspace folders but none are
    # configured.
    @[JSON::Field(key: "workspaceFolders")]
    property workspace_folders : Array(WorkspaceFolder)?
  end

  struct InitializeResult
    include Initializer
    include JSON::Serializable

    # The capabilities the language server provides.
    property capabilities : ServerCapabilities

    # Information about the server.
    @[JSON::Field(key: "serverInfo")]
    property server_info : NamedTuple(
      # The name of the server as defined by the server.
      name: String,
      # The server's version as defined by the server.
      version: String?)?
  end
end
