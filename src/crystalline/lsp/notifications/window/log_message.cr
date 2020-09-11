require "json"
require "../../tools"
require "../../base/*"
require "../notification_message"

module LSP
  # The log message notification is sent from the server to the client to ask the client to log a particular message.
  class LogMessageNotification < NotificationMessage
    @method = "window/logMessage"
    property params : LogMessageParams
  end

  struct LogMessageParams
    include Initializer
    include JSON::Serializable

    # The message type. See `MessageType`.
    property type : MessageType

    # The actual message.
    property message : String
  end
end
