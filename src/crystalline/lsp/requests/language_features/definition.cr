require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The hover request is sent from the client to the server to request hover information at a given text document position.
    class DefinitionRequest < RequestMessage((Location | Array(Location) | Array(LocationLink))?)
      @method = "textDocument/definition"
      property params : DefinitionParams
    end
  end

  struct DefinitionParams
    include TextDocumentPositionParams
    include WorkDoneProgressParams
    include PartialResultParams
    include Initializer
    include JSON::Serializable
  end
end
