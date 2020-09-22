require "json"
require "../tools"
require "./notification_message"

module LSP
  class CancelNotification < NotificationMessage
    @method = "$/cancelRequest"
    property params : CancelParams
  end

  struct CancelParams
    include Initializer
    include JSON::Serializable

    property id : RequestMessage::RequestId
  end
end
