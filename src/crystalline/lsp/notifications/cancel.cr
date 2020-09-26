require "json"
require "../tools"
require "./notification_message"

module LSP
  # The base protocol offers support for request cancellation.
  class CancelNotification < NotificationMessage
    @method = "$/cancelRequest"
    property params : CancelParams
  end

  struct CancelParams
    include Initializer
    include JSON::Serializable

    # The request id to cancel.
    property id : RequestMessage::RequestId
  end
end
