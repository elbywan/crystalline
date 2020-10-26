require "uuid"

class Crystalline::Progress
  @@token_id = Atomic(Int64).new(0)

  def initialize(token : String, @title : String, @message : String? = nil)
    @token = "#{token}/#{@@token_id.add(1)}"
  end

  def report(server, *, async = false, &cb : Proc(String?))
    create_request = LSP::WorkDoneProgressCreateRequest.new(
      id: 0,
      params: LSP::WorkDoneProgressCreateParams.new(
        token: @token,
      ),
    )

    create_request.on_response {
      if async
        spawn {
          report_callback(server, &cb)
        }
      else
        report_callback(server, &cb)
      end
    }

    server.send(create_request)
  end

  private def report_callback(server, &cb : Proc(String?))
    server.send(LSP::ProgressNotification.new(
      params: LSP::ProgressParams.new(
        token: @token,
        value: LSP::WorkDoneProgressBegin.new(
          title: @title,
          message: @message,
        ),
      ),
    ))
    end_message = cb.call
  ensure
    server.send(LSP::ProgressNotification.new(
      params: LSP::ProgressParams.new(
        token: @token,
        value: LSP::WorkDoneProgressEnd.new(
          message: end_message,
        ),
      ),
    ))
  end
end
