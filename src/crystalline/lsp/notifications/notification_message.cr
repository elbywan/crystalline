require "../message"

module LSP
  class NotificationMessage
    include Message
    include JSON::Serializable
    include Initializer

    macro inherited
      include Initializer
    end

    property method : String

    json_discriminator "method", {
      "$/progress":                      ProgressNotification,
      "$/cancelRequest":                 CancelNotification,
      initialized:                       InitializedNotification,
      exit:                              ExitNotification,
      "window/showMessage":              ShowMessageNotification,
      "window/logMessage":               LogMessageNotification,
      "textDocument/didOpen":            DidOpenNotification,
      "textDocument/didChange":          DidChangeNotification,
      "textDocument/didSave":            DidSaveNotification,
      "textDocument/didClose":           DidCloseNotification,
      "textDocument/willSave":           WillSaveNotification,
      "textDocument/publishDiagnostics": PublishDiagnosticsNotification,
    }, default: UnknownNotification
  end

  class UnknownNotification < NotificationMessage
  end
end
