require "../message"
require "../response_message"

module LSP
  class RequestMessage(Result)
    include Message
    include JSON::Serializable
    include Initializer

    macro inherited
      include Initializer
    end

    alias RequestId = Int32 | Int64 | String

    property id : RequestId
    property method : String

    @[JSON::Field(ignore: true)]
    getter? on_response : Proc(Result?, ResponseError?, Nil)?

    def on_response(raw : JSON::Any?, e : ResponseError?)
      on_response?.try &.call(Result.from_json(raw.to_json), e)
    end

    def on_response(&block : Proc(Result?, ResponseError?, Nil))
      @on_response = block
    end

    json_discriminator "method", {
      initialize:                       InitializeRequest,
      shutdown:                         ShutdownRequest,
      "window/showMessageRequest":      ShowMessageRequest,
      "window/workDoneProgress/create": WorkDoneProgressCreateRequest,
      "textDocument/willSaveWaitUntil": WillSaveWaitUntilRequest,
      "textDocument/completion":        CompletionRequest,
      "textDocument/formatting":        DocumentFormattingRequest,
      "textDocument/rangeFormatting":   DocumentRangeFormattingRequest,
      "textDocument/hover":             HoverRequest,
      "textDocument/definition":        DefinitionRequest,
      "textDocument/signatureHelp":     SignatureHelpRequest,
      "textDocument/documentSymbol":    DocumentSymbolsRequest,
    }, default: UnknownRequest
  end

  class UnknownRequest < RequestMessage(Nil)
  end
end
