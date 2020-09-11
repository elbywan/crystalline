require "json"
require "../../tools"
require "../../base/*"
require "../request_message"
require "./formatting"

module LSP
  macro finished
    # The document range formatting request is sent from the client to the server to format a given range in a document.
    class DocumentRangeFormattingRequest < RequestMessage(Array(TextEdit)?)
      @method = "textDocument/rangeFormatting"
      property params : DocumentRangeFormattingParams
    end
  end

  struct DocumentRangeFormattingParams
    include WorkDoneProgressParams
    include Initializer
    include JSON::Serializable

    # The document to format.
    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    # The range to format.
    property range : Range

    # The format options.
    property options : FormattingOptions
  end
end
