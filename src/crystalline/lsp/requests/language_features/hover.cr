require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The hover request is sent from the client to the server to request hover information at a given text document position.
    class HoverRequest < RequestMessage(Hover?)
      @method = "textDocument/hover"
      property params : HoverParams
    end
  end

  struct HoverParams
    include WorkDoneProgressParams
    include TextDocumentPositionParams
    include Initializer
    include JSON::Serializable
  end

  # The result of a hover request.
  struct Hover
    include Initializer
    include JSON::Serializable

    # The hover's content
    property contents : MarkedString | Array(MarkedString) | MarkupContent

    # An optional range is a range inside a text document
    # that is used to visualize a hover, e.g. by changing the background color.
    property range : Range?
  end

  # MarkedString can be used to render human readable text. It is either a markdown string
  # or a code-block that provides a language and a code snippet. The language identifier
  # is semantically equal to the optional language identifier in fenced code blocks in GitHub
  # issues. See https://help.github.com/articles/creating-and-highlighting-code-blocks/#syntax-highlighting
  #
  # The pair of a language and a value is an equivalent to markdown:
  # ```${language}
  # ${value}
  # ```
  #
  # Note: markdown strings will be sanitized - that means html will be escaped.
  # Deprecated: use MarkupContent instead.
  alias MarkedString = String | {language: String, value: String}
end
