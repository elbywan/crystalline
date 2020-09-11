require "./classes/**"

class Crystalline::Controller
  getter! workspace : Workspace

  def initialize(@server : LSP::Server)
    @server.start(self)
  end

  def on_init(init_params : LSP::InitializeParams) : Nil
    @workspace = Workspace.new(@server, init_params.root_uri)
  end

  def when_ready : Nil
    workspace.compile(@server)
  end

  # def on_request(message : LSP::RequestMessage(T)) : T forall T
  def on_request(message : LSP::RequestMessage)
    case message
    when LSP::DocumentFormattingRequest
      workspace.format_document(message.params).try { |(formatted_document, document)|
        range = LSP::Range.new({
          start: LSP::Position.new({line: 0, character: 0}),
          end:   LSP::Position.new({line: document.lines_nb + 1, character: 0}),
        })
        [
          LSP::TextEdit.new({
            range:    range,
            new_text: formatted_document,
          }),
        ]
      }
    when LSP::DocumentRangeFormattingRequest
      workspace.format_document(message.params).try { |(formatted_document, document)|
        [
          LSP::TextEdit.new({
            range:    message.params.range,
            new_text: formatted_document,
          }),
        ]
      }
    when LSP::HoverRequest
      file_uri = URI.parse message.params.text_document.uri
      workspace.hover(@server, file_uri, message.params.position)
    when LSP::DefinitionRequest
      file_uri = URI.parse message.params.text_document.uri
      workspace.definitions(@server, file_uri, message.params.position)
    when LSP::CompletionRequest
      file_uri = URI.parse message.params.text_document.uri
      workspace.completion(@server, file_uri, message.params.position, message.params.context.try &.trigger_character)
    else
      nil
    end
  end

  def on_notification(message : LSP::NotificationMessage) : Nil
    case message
    when LSP::DidOpenNotification
      workspace.open_document(message.params)
    when LSP::DidChangeNotification
      workspace.update_document(message.params)
    when LSP::DidCloseNotification
      workspace.close_document(message.params)
    when LSP::DidSaveNotification
      workspace.save_document(@server, message.params)
    end
  end

  def on_response(message : LSP::ResponseMessage, original_message : LSP::RequestMessage?) : Nil
    # Async.spawn_on_different_thread(@server.thread) do
    original_message.try &.on_response(message.result, message.error)
    # rescue e
    #   LSP::Log.error(exception: e) { e }
    # end
  end
end

# require "./controller/**"
