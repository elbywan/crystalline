require "json"
require "../../tools"
require "../symbol_kind"

struct LSP::WorkspaceSymbolClientCapabilities
  include JSON::Serializable
  include Initializer

  # Symbol request supports dynamic registration.
  @[JSON::Field(key: "dynamicRegistration")]
  property dynamic_registration : Bool?

  # Specific capabilities for the `SymbolKind` in the `workspace/symbol` request.

  struct SymbolKindValue
    include JSON::Serializable
    # The symbol kind values the client supports. When this
    # property exists the client also guarantees that it will
    # handle values outside its set gracefully and falls back
    # to a default value when unknown.
    #
    # If this property is not present the client only supports
    # the symbol kinds from `File` to `Array` as defined in
    # the initial version of the protocol.
    property value_set : Array(SymbolKind)?
  end

  @[JSON::Field(key: "symbolKind")]
  property symbol_kind : SymbolKindValue?
end
