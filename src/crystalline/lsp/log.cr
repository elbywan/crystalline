require "log"

module LSP
  Log = ::Log.for(self)

  class LogBackend < ::Log::IOBackend
    def initialize(@server : ::LSP::Server)
      super(server.output)
    end

    def write(entry : ::Log::Entry)
      message_type = case entry.severity
                     when ::Log::Severity::Info
                       LSP::MessageType::Info
                     when ::Log::Severity::Warn
                       LSP::MessageType::Warning
                     when ::Log::Severity::Error, ::Log::Severity::Fatal
                       LSP::MessageType::Error
                     else
                       LSP::MessageType::Log
                     end
      log_message = LSP::LogMessageNotification.new(
        params: LSP::LogMessageParams.new(type: message_type, message: entry.message),
      )
      @server.send(log_message, do_not_log: true)
    end
  end
end
