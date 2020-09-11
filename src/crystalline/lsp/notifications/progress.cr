require "json"
require "../tools"
require "./notification_message"

module LSP
  alias ProgressToken = Int32 | String

  class ProgressNotification < NotificationMessage
    @method = "$/progress"
    property params : ProgressParams
  end

  struct ProgressParams
    include Initializer
    include JSON::Serializable

    # The progress token provided by the client or server.
    property token : ProgressToken

    # The progress data.
    property value : WorkDoneProgressBegin | WorkDoneProgressReport | WorkDoneProgressEnd
  end
end
