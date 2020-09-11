require "json"
require "../../tools"
require "../../base/*"
require "../notification_message"

module LSP
  # The show message notification is sent from a server to a client to ask the client to display a particular message in the user interface.
  class ShowMessageNotification < NotificationMessage
    @method = "window/showMessage"
    property params : ShowMessageParams
  end

  struct ShowMessageParams
    include Initializer
    include JSON::Serializable

    # The message type. See `MessageType`.
    property type : MessageType

    # The actual message.
    property message : String
  end
end
