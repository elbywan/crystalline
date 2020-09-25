require "./ext/**"
require "./base/**"
require "./notifications/**"
require "./requests/**"
require "./response_message"
require "./tools"
require "./log"

# A Language Server Protocol generic implementation.
#
# This server is basically an I/O loop receiving, replying, sending message and handling exceptions.
# Actual actions are delegated to an external class.
class LSP::Server
  # True if the server is shutting down.
  @shutdown = false

  # Input from which messages are received.
  getter input : IO
  # Output to which the messages are sent.
  getter output : IO
  # The broadcasted server capabilites.
  getter server_capabilities : LSP::ServerCapabilities
  # A list of requests that were sent to clients to keep track of the ID and kind.
  getter requests_sent : Hash(RequestMessage::RequestId, LSP::Message) = {} of RequestMessage::RequestId => LSP::Message
  # Incremental.
  @max_request_id = Atomic(Int64).new(0)
  # Lock to prevent interleaving.
  @out_lock = Mutex.new(:reentrant)
  # This server thread, that should not get blocked by all means.
  getter thread : Thread

  # Dummy default server capabilites.
  DEFAULT_SERVER_CAPABILITIES = LSP::ServerCapabilities.new({
    text_document_sync: LSP::TextDocumentSyncKind::Incremental,
  })

  # Initialize a new LSP Server with the provided options.
  def initialize(@input = STDIN, @output = STDOUT, @server_capabilities = DEFAULT_SERVER_CAPABILITIES)
    @thread = Thread.current
    LSP::Log.backend = LogBackend.new(self)
    # ::Log.setup(:debug, LSP::Log.backend.not_nil!)
    # Log.backend = ::Log::IOBackend.new(File.new "./crystalline_logs.txt", mode: "a+")
  end

  # Send a message to the client.
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

  # Send an array of messages to the client.
  def send(messages : Array, *, do_not_log = false)
    messages.each do |message|
      send(message: message, do_not_log: do_not_log)
    end
  end

  # Reply to a *request* initiated by the client with the provided *result*.
  def reply(request : LSP::RequestMessage, *, result : T, do_not_log = false) forall T
    request.id = @max_request_id.add(1)
    response_message = LSP::ResponseMessage(T).new({id: request.id, result: result})
    send(message: response_message, do_not_log: do_not_log)
  end

  # Reply to a *request* initiated by the client with an error message containing the *exception* details.
  def reply(request : LSP::RequestMessage, *, exception, do_not_log = false)
    response_message = LSP::ResponseMessage(Nil).new({id: request.id, error: LSP::ResponseError.new(exception)})
    send(message: response_message, do_not_log: do_not_log)
  end

  # Read a client message and deserialize it.
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

    # Successive deserialization steps because the messages structure overlap (they have similar fields).
    # So we go from the stricter type and go down.
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

  # The initial handshake.
  private def handshake(controller)
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

  # Callback that gets executed when an exception is thrown.
  # Takes care of replying to the *message* with the correct information extracted from the exception.
  private def on_exception(message, e)
    Log.error(exception: e) { e }
    if message.is_a? LSP::RequestMessage
      reply(request: message, exception: e)
    end
  end

  # The main I/O loop.
  private def server_loop(controller)
    loop do
      # Read a message.
      message = self.class.read(@input)

      # Perform special actions if needed.
      raise LSP::Exception.new(code: :invalid_request, message: "Server is shutting down.") if @shutdown
      exit(0) if message.is_a? LSP::ExitNotification

      if message.is_a? LSP::RequestMessage
        request_message = message.as(LSP::RequestMessage)
        if message.is_a? LSP::ShutdownRequest
          @shutdown = true
          reply(request: request_message, result: nil)
        elsif controller.responds_to? :on_request
          # Delegate to the controller in a separate thread to prevent blocking this loop.
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
          # Delegate to the controller.
          controller.on_notification(message.as(LSP::NotificationMessage))
        end
      elsif message.is_a? LSP::ResponseMessage
        response_message = message.as(LSP::ResponseMessage)
        original_message = requests_sent.delete(response_message.id)
        if controller.responds_to? :on_response
          # Delegate to the controller in a separate thread to prevent blocking this loop.
          Async.spawn_on_different_thread(thread) do
            controller.on_response(response_message, original_message.try &.as(RequestMessage))
          rescue e
            on_exception(message, e)
          end
        end
      end
    rescue IO::Error
      # Break on IO error because the connection is certainly closed.
      # In this case, just terminate the loop.
      break
    rescue e
      on_exception(message, e)
    end
  end

  def start(controller)
    Log.debug { "Crystalline LSP server is initializing…" }

    handshake(controller)

    if controller.responds_to? :when_ready
      begin
        # Give the chance to the controller to perform blocking initialization tasks before running the loop.
        controller.when_ready
      rescue e
        Log.warn(exception: e) { "Error during initialization: #{e}" }
      end
    end

    Log.info { "Crystalline LSP server is ready." }

    server_loop(controller)
  end
end
