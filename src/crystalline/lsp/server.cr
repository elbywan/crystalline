require "./ext/**"
require "./base/**"
require "./notifications/**"
require "./requests/**"
require "./response_message"
require "./tools"
require "./log"

class LSP::Server
  @shutdown = false

  getter input : IO
  getter output : IO
  getter server_capabilities : LSP::ServerCapabilities
  getter requests_sent : Hash(RequestMessage::RequestId, LSP::Message) = {} of RequestMessage::RequestId => LSP::Message
  @max_request_id = Atomic(Int64).new(0)
  @in_lock = Mutex.new(:reentrant)
  @out_lock = Mutex.new(:reentrant)
  getter thread : Thread

  DEFAULT_SERVER_CAPABILITIES = LSP::ServerCapabilities.new({
    text_document_sync: LSP::TextDocumentSyncKind::Incremental,
  })

  def initialize(@input = STDIN, @output = STDOUT, @server_capabilities = DEFAULT_SERVER_CAPABILITIES)
    @thread = Thread.current
    LSP::Log.backend = LogBackend.new(self)
    # ::Log.setup(:debug, LSP::Log.backend.not_nil!)
    # Log.backend = ::Log::IOBackend.new(File.new "./crystalline_logs.txt", mode: "a+")
  end

  def send(message : LSP::Message, *, do_not_log = false)
    if message.is_a? LSP::RequestMessage
      @requests_sent[message.id] = message
    end
    json = message.to_json
    Log.debug { "[Server -> Client]\n" + json } unless do_not_log
    @out_lock.synchronize {
      @output << "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
      @output.flush
    }
  end

  def send(client_messages : Array, *, do_not_log = false)
    client_messages.each do |client_message|
      send(message: client_message, do_not_log: do_not_log)
    end
  end

  def reply(request : LSP::RequestMessage, *, result : T, do_not_log = false) forall T
    request.id = @max_request_id.add(1)
    response_message = LSP::ResponseMessage(T).new({id: request.id, result: result})
    send(message: response_message, do_not_log: do_not_log)
  end

  def reply(request : LSP::RequestMessage, *, exception, do_not_log = false)
    response_message = LSP::ResponseMessage(Nil).new({id: request.id, error: LSP::ResponseError.new(exception)})
    send(message: response_message, do_not_log: do_not_log)
  end

  protected def self.read(io : IO)
    if io.responds_to? :blocking
      io.blocking = false
    end
    content_length = uninitialized Int32
    content_type = "application/vscode-jsonrpc; charset=utf-8"

    loop do
      break if (header = io.gets).nil?
      header = header.chomp
      if header.size > 0
        name, value = header.split(':')
        case name
        when "Content-Length"
          content_length = value.to_i
        when "Content-Type"
          content_type = value
        else
          raise "Unrecognized header #{name}"
        end
      else
        break
      end
    end

    raise "Content-Length is mandatory" if content_length.nil?

    content = Bytes.new(content_length)
    io.read_fully(content)
    content_str = String.new(content)

    begin
      message = LSP::RequestMessage.from_json(content_str)
    rescue
      begin
        message = LSP::ResponseMessage(JSON::Any?).from_json(content_str)
      rescue
        message = LSP::NotificationMessage.from_json(content_str)
      end
    end
    Log.debug { "[Client -> Server](#{message.class})\n#{"Content-Length:#{content_length}"}\n#{content_str}" }
    message
  end

  private def initialize_routine(controller)
    loop do
      initialize_message = self.class.read(@input)
      if initialize_message.is_a? LSP::InitializeRequest
        if controller.responds_to? :on_init
          init_result = controller.on_init(initialize_message.params)
        else
          init_result = nil
        end
        reply(initialize_message, result: init_result || LSP::InitializeResult.new({capabilities: @server_capabilities}))
        break
      elsif initialize_message.is_a? LSP::RequestMessage
        reply(initialize_message, exception: LSP::Exception.new(
          code: :server_not_initialized,
          message: "Expecting an initialize request but received #{initialize_message.method}.",
        ))
      end
    rescue IO::Error
      exit(1)
    rescue e
      Log.error(exception: e) { e }
    end
  end

  private def on_exception(message, e)
    Log.error(exception: e) { e }
    if message.is_a? LSP::RequestMessage
      reply(request: message, exception: e)
    end
  end

  private def message_loop(controller)
    loop do
      message = @in_lock.synchronize { self.class.read(@input) }

      raise LSP::Exception.new(code: :invalid_request, message: "Server is shutting down.") if @shutdown
      exit(0) if message.is_a? LSP::ExitNotification

      if message.is_a? LSP::RequestMessage
        request_message = message.as(LSP::RequestMessage)
        if message.is_a? LSP::ShutdownRequest
          @shutdown = true
          reply(request: request_message, result: nil)
        elsif controller.responds_to? :on_request
          Async.spawn_on_different_thread(thread) do
            result = controller.on_request(request_message)
            reply(request: request_message, result: result)
          rescue e
            on_exception(message, e)
          end
        else
          reply(request: request_message, result: nil)
        end
      elsif message.is_a? LSP::NotificationMessage
        if controller.responds_to? :on_notification
          controller.on_notification(message.as(LSP::NotificationMessage))
        end
      elsif message.is_a? LSP::ResponseMessage
        response_message = message.as(LSP::ResponseMessage)
        original_message = requests_sent.delete(response_message.id)
        if controller.responds_to? :on_response
          Async.spawn_on_different_thread(thread) do
            controller.on_response(response_message, original_message.try &.as(RequestMessage))
          rescue e
            on_exception(message, e)
          end
        end
      end
    rescue IO::Error
      break
    rescue e
      on_exception(message, e)
    end
  end

  def start(controller)
    Log.debug { "Crystalline LSP server is initializing…" }

    initialize_routine(controller)

    if controller.responds_to? :when_ready
      begin
        controller.when_ready
      rescue e
        Log.warn(exception: e) { "Error during initialization: #{e}" }
      end
    end

    Log.info { "Crystalline LSP server is ready." }

    message_loop(controller)
  end
end
