require "json"
require "../../tools"
require "../markup_content"
require "../completion_item"
require "../symbol_kind"
require "../code_action_kind"
require "../diagnostic"

# Text document specific client capabilities.
struct LSP::TextDocumentClientCapabilities
  include JSON::Serializable
  include Initializer

  property synchronization : TextDocumentSyncClientCapabilities?

  struct TextDocumentSyncClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether text document synchronization supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # The client supports sending will save notifications.
    @[JSON::Field(key: "willSave")]
    property will_save : Bool?

    # The client supports sending a will save request and
    # waits for a response providing text edits which will
    # be applied to the document before it is saved.
    @[JSON::Field(key: "willSaveWaitUntil")]
    property will_save_wait_until : Bool?

    # The client supports did save notifications.
    @[JSON::Field(key: "didSave")]
    property did_save : Bool?
  end

  # Capabilities specific to the `textDocument/completion` request.
  property completion : CompletionClientCapabilities?

  struct CompletionClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether completion supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    struct CompletionItem
      include JSON::Serializable
      include Initializer

      # Client supports snippets as insert text.
      #
      # A snippet can define tab stops and placeholders with `$1`, `$2`
      # and `${3:foo}`. `$0` defines the final tab stop, it defaults to
      # the end of the snippet. Placeholders with equal identifiers are linked,
      # that is typing in one will update others too.
      @[JSON::Field(key: "snippetSupport")]
      property snippet_support : Bool?

      # Client supports commit characters on a completion item.
      @[JSON::Field(key: "commitCharactersSupport")]
      property commit_characters_support : Bool?

      # Client supports the follow content formats for the documentation
      # property. The order describes the preferred format of the client.
      @[JSON::Field(key: "documentationFormat")]
      property documentation_format : Array(MarkupKind)?

      # Client supports the deprecated property on a completion item.
      @[JSON::Field(key: "deprecatedSupport")]
      property deprecated_support : Bool?

      # Client supports the preselect property on a completion item.
      @[JSON::Field(key: "preselectSupport")]
      property preselect_support : Bool?

      struct TagSupport
        include JSON::Serializable
        include Initializer

        @[JSON::Field(key: "valueSet")]
        property value_set : Array(CompletionItemTag)
      end

      # Client supports the tag property on a completion item. Clients supporting
      # tags have to handle unknown tags gracefully. Clients especially need to
      # preserve unknown tags when sending a completion item back to the server in
      # a resolve call.
      @[JSON::Field(key: "tagSupport")]
      property tag_support : TagSupport?
    end

    # The client supports the following `CompletionItem` specific
    # capabilities.
    @[JSON::Field(key: "completionItem")]
    property completion_item : CompletionItem?

    struct CompletionItemKindValue
      include JSON::Serializable
      include Initializer

      # The completion item kind values the client supports. When this
      # property exists the client also guarantees that it will
      # handle values outside its set gracefully and falls back
      # to a default value when unknown.
      #
      # If this property is not present the client only supports
      # the completion items kinds from `Text` to `Reference` as defined in
      # the initial version of the protocol.
      @[JSON::Field(key: "valueSet")]
      property value_set : Array(CompletionItemKind)?
    end

    @[JSON::Field(key: "completionItemKind")]
    property completion_item_kind : CompletionItemKindValue?

    # The client supports to send additional context information for a
    # `textDocument/completion` request.
    @[JSON::Field(key: "contextSupport")]
    property context_support : Bool?
  end

  # Capabilities specific to the `textDocument/hover` request.
  property hover : HoverClientCapabilities?

  struct HoverClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether hover supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # Client supports the follow content formats for the content
    # property. The order describes the preferred format of the client.
    @[JSON::Field(key: "contentFormat")]
    property content_format : Array(MarkupKind)?
  end

  # Capabilities specific to the `textDocument/signatureHelp` request.
  @[JSON::Field(key: "signatureHelp")]
  property signature_help : SignatureHelpClientCapabilities?

  struct SignatureHelpClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether signature help supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    struct SignatureInformationValue
      include JSON::Serializable
      include Initializer

      # Client supports the follow content formats for the documentation
      # property. The order describes the preferred format of the client.
      @[JSON::Field(key: "documentationFormat")]
      property documentation_format : Array(MarkupKind)?

      struct ParameterInformationValue
        include JSON::Serializable
        include Initializer

        # The client supports processing label offsets instead of a
        # simple label string.
        @[JSON::Field(key: "labelOffsetSupport")]
        property label_offset_support : Bool?
      end

      # Client capabilities specific to parameter information.
      @[JSON::Field(key: "parameterInformation")]
      property parameter_information : ParameterInformationValue?
    end

    # The client supports the following `SignatureInformation`
    # specific properties.
    @[JSON::Field(key: "signatureInformation")]
    property signature_information : SignatureInformationValue?

    # The client supports to send additional context information for a
    # `textDocument/signatureHelp` request. A client that opts into
    # contextSupport will also support the `retriggerCharacters` on
    # `SignatureHelpOptions`.
    @[JSON::Field(key: "contextSupport")]
    property context_support : Bool?
  end

  # Capabilities specific to the `textDocument/declaration` request.
  property declaration : DeclarationClientCapabilities?

  struct DeclarationClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether declaration supports dynamic registration. If this is set to `true`
    # the client supports the new `DeclarationRegistrationOptions` return value
    # for the corresponding server capability as well.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # The client supports additional metadata in the form of declaration links.
    @[JSON::Field(key: "linkSupport")]
    property link_support : Bool?
  end

  # Capabilities specific to the `textDocument/definition` request.
  property definition : DefinitionClientCapabilities?

  struct DefinitionClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether definition supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # The client supports additional metadata in the form of definition links.
    @[JSON::Field(key: "linkSupport")]
    property link_support : Bool?
  end

  # Capabilities specific to the `textDocument/typeDefinition` request.
  @[JSON::Field(key: "typeDefinition")]
  property type_definition : TypeDefinitionClientCapabilities?

  struct TypeDefinitionClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether implementation supports dynamic registration. If this is set to `true`
    # the client supports the new `TypeDefinitionRegistrationOptions` return value
    # for the corresponding server capability as well.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # The client supports additional metadata in the form of definition links.
    @[JSON::Field(key: "linkSupport")]
    property link_support : Bool?
  end

  # Capabilities specific to the `textDocument/implementation` request.
  property implementation : ImplementationClientCapabilities?

  struct ImplementationClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether implementation supports dynamic registration. If this is set to `true`
    # the client supports the new `ImplementationRegistrationOptions` return value
    # for the corresponding server capability as well.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # The client supports additional metadata in the form of definition links.
    @[JSON::Field(key: "linkSupport")]
    property link_support : Bool?
  end

  # Capabilities specific to the `textDocument/references` request.
  property references : ReferenceClientCapabilities?

  struct ReferenceClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether references supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end

  # Capabilities specific to the `textDocument/documentHighlight` request.
  @[JSON::Field(key: "documentHighlight")]
  property document_highlight : DocumentHighlightClientCapabilities?

  struct DocumentHighlightClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether document highlight supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end

  # Capabilities specific to the `textDocument/documentSymbol` request.
  @[JSON::Field(key: "documentSymbol")]
  property document_symbol : DocumentSymbolClientCapabilities?

  struct DocumentSymbolClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether document symbol supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    struct SymbolKindValue
      include Initializer
      include JSON::Serializable

      # The symbol kind values the client supports. When this
      # property exists the client also guarantees that it will
      # handle values outside its set gracefully and falls back
      # to a default value when unknown.
      #
      # If this property is not present the client only supports
      # the symbol kinds from `File` to `Array` as defined in
      # the initial version of the protocol.
      @[JSON::Field(key: "valueSet")]
      property value_set : Array(SymbolKind)?
    end

    # Specific capabilities for the `SymbolKind` in the `textDocument/documentSymbol` request.
    @[JSON::Field(key: "symbolKind")]
    property symbol_kind : SymbolKindValue?

    # The client supports hierarchical document symbols.
    @[JSON::Field(key: "hierarchicalDocumentSymbolSupport")]
    property hierarchical_document_symbol_support : Bool?
  end

  # Capabilities specific to the `textDocument/codeAction` request.
  @[JSON::Field(key: "codeAction")]
  property code_action : CodeActionClientCapabilities?

  struct CodeActionClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether code action supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    struct CodeActionLiteralSupportValue
      include Initializer
      include JSON::Serializable

      # The code action kind is supported with the following value set.
      @[JSON::Field(key: "codeActionKind")]
      property code_action_kind : CodeActionKindValue?

      struct CodeActionKindValue
        include JSON::Serializable
        include Initializer

        # The code action kind values the client supports. When this
        # property exists the client also guarantees that it will
        # handle values outside its set gracefully and falls back
        # to a default value when unknown.
        @[JSON::Field(key: "valueSet")]
        property value_set : Array(CodeActionKind)?
      end
    end

    # The client supports code action literals as a valid
    # response of the `textDocument/codeAction` request.
    @[JSON::Field(key: "codeActionLiteralSupport")]
    property code_action_literal_support : CodeActionLiteralSupportValue?

    # Whether code action supports the `isPreferred` property.
    @[JSON::Field(key: "isPreferredSupport")]
    property is_preferred_support : Bool?
  end

  # Capabilities specific to the `textDocument/codeLens` request.
  @[JSON::Field(key: "codeLens")]
  property code_lens : CodeLensClientCapabilities?

  struct CodeLensClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether code lens supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end

  # Capabilities specific to the `textDocument/documentLink` request.
  @[JSON::Field(key: "documentLink")]
  property document_link : DocumentLinkClientCapabilities?

  struct DocumentLinkClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether document link supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # Whether the client supports the `tooltip` property on `DocumentLink`.
    @[JSON::Field(key: "tooltipSupport")]
    property tooltip_support : Bool?
  end

  # Capabilities specific to the `textDocument/documentColor` and the
  # `textDocument/colorPresentation` request.
  @[JSON::Field(key: "colorProvider")]
  property color_provider : DocumentColorClientCapabilities?

  struct DocumentColorClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether document color supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end

  # Capabilities specific to the `textDocument/formatting` request.
  property formatting : DocumentFormattingClientCapabilities?

  struct DocumentFormattingClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether formatting color supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end

  # Capabilities specific to the `textDocument/rangeFormatting` request.
  @[JSON::Field(key: "rangeFormatting")]
  property range_formatting : DocumentRangeFormattingClientCapabilities?

  struct DocumentRangeFormattingClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether formatting supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end

  # Capabilities specific to the `textDocument/onTypeFormatting` request.
  @[JSON::Field(key: "onTypeFormatting")]
  property on_type_formatting : DocumentOnTypeFormattingClientCapabilities?

  struct DocumentOnTypeFormattingClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether on type formatting supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end

  # Capabilities specific to the `textDocument/rename` request.
  property rename : RenameClientCapabilities?

  struct RenameClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether rename supports dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # Client supports testing for validity of rename operations
    # before execution.
    @[JSON::Field(key: "prepareSupport")]
    property prepare_support : Bool?
  end

  # Capabilities specific to the `textDocument/publishDiagnostics` notification.
  @[JSON::Field(key: "publishDiagnostics")]
  property publish_diagnostics : PublishDiagnosticsClientCapabilities?

  struct PublishDiagnosticsClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether the clients accepts diagnostics with related information.
    @[JSON::Field(key: "relatedInformation")]
    property related_information : Bool?

    struct TagSupportValue
      include JSON::Serializable
      include Initializer

      # The tags supported by the client.
      @[JSON::Field(key: "valueSet")]
      property value_set : Array(DiagnosticTag)
    end

    # Client supports the tag property to provide meta data about a diagnostic.
    # Clients supporting tags have to handle unknown tags gracefully.
    @[JSON::Field(key: "tag_support")]
    property tag_support : TagSupportValue?

    # Whether the client interprets the version property of the
    # `textDocument/publishDiagnostics` notification's parameter.
    @[JSON::Field(key: "versionSupport")]
    property version_support : Bool?
  end

  # Capabilities specific to the `textDocument/foldingRange` request.
  @[JSON::Field(key: "foldingRange")]
  property folding_range : FoldingRangeClientCapabilities?

  struct FoldingRangeClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether implementation supports dynamic registration for folding range providers. If this is set to `true`
    # the client supports the new `FoldingRangeRegistrationOptions` return value for the corresponding server
    # capability as well.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?

    # The maximum number of folding ranges that the client prefers to receive per document. The value serves as a
    # hint, servers are free to follow the limit.
    @[JSON::Field(key: "rangeLimit")]
    property range_limit : Int32?

    # If set, the client signals that it only supports folding complete lines. If set, client will
    # ignore specified `startCharacter` and `endCharacter` properties in a FoldingRange.
    @[JSON::Field(key: "lineFoldingOnly")]
    property line_folding_only : Bool?
  end

  # Capabilities specific to the `textDocument/selectionRange` request.
  @[JSON::Field(key: "selectionRange")]
  property selection_range : SelectionRangeClientCapabilities?

  struct SelectionRangeClientCapabilities
    include Initializer
    include JSON::Serializable

    # Whether implementation supports dynamic registration for selection range providers. If this is set to `true`
    # the client supports the new `SelectionRangeRegistrationOptions` return value for the corresponding server
    # capability as well.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
  end
end
