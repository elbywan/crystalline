require "./classes/**"

class Crystalline::Controller
  # The project workspace.
  getter! workspace : Workspace
  # A list of requests that are pending, used when receiving a cancel request.
  @pending_requests : Set(LSP::RequestMessage::RequestId) = Set(LSP::RequestMessage::RequestId).new
  # Used to process certain requests synchronously.
  @documents_lock = Mutex.new
  @compiler_lock = Mutex.new

  def initialize(@server : LSP::Server)
    @server.start(self)
  end

  def on_init(init_params : LSP::InitializeParams) : Nil
    @workspace = Workspace.new(@server, init_params.root_uri)
  end

  def when_ready : Nil
    # Compile the workspace at once.
    spawn same_thread: true do
      workspace.compile(@server, ignore_diagnostics: @server.client_capabilities.ignore_diagnostics?)
    end
  end

  # The compiler unfortunately prevents declaring the following signature for the time being:
  # def on_request(message : LSP::RequestMessage(T)) : T forall T
  def on_request(message : LSP::RequestMessage)
    @pending_requests << message.id
    case message
    when LSP::DocumentFormattingRequest
      @documents_lock.synchronize {
        workspace.format_document(message.params).try { |(formatted_document, document)|
          range = LSP::Range.new(
            start: LSP::Position.new(line: 0, character: 0),
            end: LSP::Position.new(line: document.lines_nb + 1, character: 0),
          )
          [
            LSP::TextEdit.new(
              range: range,
              new_text: formatted_document,
            ),
          ]
        }
      }
    when LSP::DocumentRangeFormattingRequest
      @documents_lock.synchronize {
        workspace.format_document(message.params).try { |(formatted_document, document)|
          [
            LSP::TextEdit.new(
              range: message.params.range,
              new_text: formatted_document,
            ),
          ]
        }
      }
    when LSP::HoverRequest
      @compiler_lock.synchronize do
        return nil unless @pending_requests.includes? message.id
        file_uri = URI.parse message.params.text_document.uri
        workspace.hover(@server, file_uri, message.params.position)
      end
    when LSP::DefinitionRequest
      @compiler_lock.synchronize do
        return nil unless @pending_requests.includes? message.id
        file_uri = URI.parse message.params.text_document.uri
        workspace.definitions(@server, file_uri, message.params.position)
      end
    when LSP::CompletionRequest
      @compiler_lock.synchronize do
        return nil unless @pending_requests.includes? message.id
        file_uri = URI.parse message.params.text_document.uri
        workspace.completion(@server, file_uri, message.params.position, message.params.context.try &.trigger_character)
      end
    when LSP::DocumentSymbolsRequest
      @documents_lock.synchronize do
        file_uri = URI.parse message.params.text_document.uri
        document_symbols = workspace.document_symbols(@server, file_uri)

        if @server.client_capabilities.text_document.try &.document_symbol.try &.hierarchical_document_symbol_support
          document_symbols
        else
          document_symbols.try &.reduce([] of LSP::SymbolInformation) { |acc, document_symbol|
            acc.concat(document_symbol.to_symbol_information_array(message.params.text_document.uri))
          }
        end
      end
    else
      nil
    end
  rescue e : Crystal::TypeException
    LSP::Log.warn(exception: e) { e.to_s }
    nil
  rescue e : Crystal::SyntaxException
    LSP::Log.warn(exception: e) { e.to_s }
    nil
  ensure
    @pending_requests.delete message.id
  end

  def on_notification(message : LSP::NotificationMessage) : Nil
    case message
    when LSP::DidOpenNotification
      @documents_lock.synchronize {
        workspace.open_document(message.params)
      }
    when LSP::DidChangeNotification
      @documents_lock.synchronize {
        workspace.update_document(@server, message.params)
      }
    when LSP::DidCloseNotification
      @documents_lock.synchronize {
        workspace.close_document(message.params)
      }
    when LSP::DidSaveNotification
      @documents_lock.synchronize {
        workspace.save_document(@server, message.params)
      }
    when LSP::CancelNotification
      @pending_requests.delete message.params.id
    end
  rescue e : Crystal::TypeException
    LSP::Log.warn(exception: e) { e.to_s }
  rescue e : Crystal::SyntaxException
    LSP::Log.warn(exception: e) { e.to_s }
  end

  def on_response(message : LSP::ResponseMessage, original_message : LSP::RequestMessage?) : Nil
    original_message.try &.on_response(message.result, message.error)
  rescue e : Crystal::TypeException
    LSP::Log.warn(exception: e) { e.to_s }
  rescue e : Crystal::SyntaxException
    LSP::Log.warn(exception: e) { e.to_s }
  end
end
