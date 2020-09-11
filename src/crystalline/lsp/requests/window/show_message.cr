require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The show message request is sent from a server to a client to ask the client to display a particular message in the user interface.
    # In addition to the show message notification the request allows to pass actions and to wait for an answer from the client.
    class ShowMessageRequest < RequestMessage(MessageActionItem?)
      @method = "window/showMessageRequest"
      property params : ShowMessageRequestParams
    end
  end

  struct ShowMessageRequestParams
    include Initializer
    include JSON::Serializable

    # The message type. See {@link MessageType}
    property type : MessageType

    # The actual message
    property message : String

    # The message action items to present.
    property actions : Array(MessageActionItem)?
  end

  struct MessageActionItem
    include Initializer
    include JSON::Serializable

    # A short title like 'Retry', 'Open Log' etc.
    property title : String
  end
end
