require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The window/workDoneProgress/create request is sent from the server to the client to ask the client to create a work done progress.
    class WorkDoneProgressCreateRequest < RequestMessage(Nil)
      @method = "window/workDoneProgress/create"
      property params : WorkDoneProgressCreateParams
    end
  end

  struct WorkDoneProgressCreateParams
    include Initializer
    include JSON::Serializable

    # The token to be used to report progress.
    property token : ProgressToken
  end
end
