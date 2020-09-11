require "../base/*"
require "./notification_message"

module LSP
  # A notification to ask the server to exit its process.
  # The server should exit with success code 0 if the shutdown request has been received before; otherwise with error code 1.
  class ExitNotification < NotificationMessage
    @method = "exit"
    property params : Nil
  end
end
