require "../base/*"
require "./request_message"

module LSP
  # The shutdown request is sent from the client to the server.
  #
  # It asks the server to shut down, but to not exit (otherwise the response might not be delivered correctly to the client).
  # There is a separate exit notification that asks the server to exit.
  # Clients must not send any notifications other than exit or requests to a server to which they have sent a shutdown request.
  # If a server receives requests after a shutdown request those requests should error with InvalidRequest.
  class ShutdownRequest < RequestMessage(Nil)
    @method = "shutdown"
    property params : Nil
  end
end
