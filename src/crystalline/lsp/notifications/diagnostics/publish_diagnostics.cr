require "json"
require "../../tools"
require "../../base/*"

module LSP
  class PublishDiagnosticsNotification < NotificationMessage
    @method = "textDocument/publishDiagnostics"
    property params : PublishDiagnosticsParams
  end

  struct PublishDiagnosticsParams
    include Initializer
    include JSON::Serializable

    # The URI for which diagnostic information is reported.
    property uri : String

    # Optional: the version number of the document the diagnostics are published for.
    property version : Int32?

    # An array of diagnostic information items.
    property diagnostics : Array(Diagnostic)
  end
end
