require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The document formatting request is sent from the client to the server to format a whole document.
    class DocumentFormattingRequest < RequestMessage(Array(TextEdit)?)
      @method = "textDocument/formatting"
      property params : DocumentFormattingParams
    end
  end

  struct DocumentFormattingParams
    include WorkDoneProgressParams
    include Initializer
    include JSON::Serializable

    # The document to format.
    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    # The format options.
    property options : FormattingOptions
  end

  # Value-object describing what options formatting should use.
  struct FormattingOptions
    include Initializer
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    # Size of a tab in spaces.
    @[JSON::Field(key: "tabSize")]
    property tab_size : Int32

    # Prefer spaces over tabs.
    @[JSON::Field(key: "insertSpaces")]
    property insert_spaces : Bool

    # Trim trailing whitespace on a line.
    @[JSON::Field(key: "trimTrailingWhitespace")]
    property trim_trailing_whitespace : Bool?

    # Insert a newline character at the end of the file if one does not exist.
    @[JSON::Field(key: "insertFinalNewline")]
    property insert_final_newline : Bool?

    # Trim all newlines after the final newline at the end of the file.
    @[JSON::Field(key: "trimFinalNewlines")]
    property trim_final_newlines : Bool?
  end
end
