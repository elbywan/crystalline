require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The document symbol request is sent from the client to the server.
    class DocumentSymbolsRequest < RequestMessage((Array(DocumentSymbol) | Array(SymbolInformation))?)
      @method = "textDocument/documentSymbol"
      property params : DocumentSymbolParams
    end
  end

  struct DocumentSymbolParams
    include WorkDoneProgressParams
    include PartialResultParams
    include Initializer
    include JSON::Serializable

    # The text document.
    @[JSON::Field(key: "textDocument")]
    property text_document : LSP::TextDocumentIdentifier
  end

  # Represents programming constructs like variables, classes, interfaces etc. that appear in a document. Document symbols can be
  # hierarchical and they have two ranges: one that encloses its definition and one that points to its most interesting range,
  # e.g. the range of an identifier.
  struct DocumentSymbol
    include Initializer
    include JSON::Serializable

    # The name of this symbol. Will be displayed in the user interface and therefore must not be
    # an empty string or a string only consisting of white spaces.
    property name : String

    # More detail for this symbol, e.g the signature of a function.
    property detail : String?

    # The kind of this symbol.
    property kind : LSP::SymbolKind

    # Indicates if this symbol is deprecated.
    property deprecated : Bool?

    # The range enclosing this symbol not including leading/trailing whitespace but everything else
    # like comments. This information is typically used to determine if the clients cursor is
    # inside the symbol to reveal in the symbol in the UI.
    property range : LSP::Range

    # The range that should be selected and revealed when this symbol is being picked, e.g the name of a function.
    # Must be contained by the `range`.
    @[JSON::Field(key: "selectionRange")]
    property selection_range : LSP::Range

    # Children of this symbol, e.g. properties of a class.
    property children : Array(DocumentSymbol)?
  end

  # Represents information about programming constructs like variables, classes,
  # interfaces etc.
  struct SymbolInformation
    include Initializer
    include JSON::Serializable

    # The name of this symbol.
    property name : String

    # The kind of this symbol.
    property kind : SymbolKind

    # Indicates if this symbol is deprecated.
    property deprecated : Bool?

    # The location of this symbol. The location's range is used by a tool
    # to reveal the location in the editor. If the symbol is selected in the
    # tool the range's start information is used to position the cursor. So
    # the range usually spans more then the actual symbol's name and does
    # normally include things like visibility modifiers.
    #
    # The range doesn't have to denote a node range in the sense of a abstract
    # syntax tree. It can therefore not be used to re-construct a hierarchy of
    # the symbols.
    property location : LSP::Location

    # The name of the symbol containing this symbol. This information is for
    # user interface purposes (e.g. to render a qualifier in the user interface
    # if necessary). It can't be used to re-infer a hierarchy for the document
    # symbols.
    @[JSON::Field(key: "containerName")]
    property container_name : String?
  end
end
