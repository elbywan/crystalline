require "json"
require "../../tools"
require "../../base/*"
require "./*"

module LSP
  struct ServerCapabilities
    include Initializer
    include JSON::Serializable

    # Defines how text documents are synced. Is either a detailed structure defining each notification or
    # for backwards compatibility the TextDocumentSyncKind number. If omitted it defaults to `TextDocumentSyncKind.None`.
    @[JSON::Field(key: "textDocumentSync")]
    property text_document_sync : (TextDocumentSyncOptions | TextDocumentSyncKind)?

    # The server provides completion support.
    @[JSON::Field(key: "completionProvider")]
    property completion_provider : CompletionOptions?

    # The server provides hover support.
    @[JSON::Field(key: "hoverProvider")]
    property hover_provider : (Bool | HoverOptions)?

    # The server provides signature help support.
    @[JSON::Field(key: "signatureHelpProvider")]
    property signature_help_provider : SignatureHelpOptions?

    # The server provides go to declaration support.
    @[JSON::Field(key: "declarationProvider")]
    property declaration_provider : (Bool | DeclarationOptions | DeclarationRegistrationOptions)?

    # The server provides goto definition support.
    @[JSON::Field(key: "definitionProvider")]
    property definition_provider : (Bool | DefinitionOptions)?

    # The server provides goto type definition support.
    @[JSON::Field(key: "typeDefinitionProvider")]
    property type_definition_provider : (Bool | TypeDefinitionOptions | TypeDefinitionRegistrationOptions)?

    # The server provides goto implementation support.
    @[JSON::Field(key: "implementationProvider")]
    property implementation_provider : (Bool | ImplementationOptions | ImplementationRegistrationOptions)?

    # The server provides find references support.
    @[JSON::Field(key: "referencesProvider")]
    property references_provider : (Bool | ReferenceOptions)?

    # The server provides document highlight support.
    @[JSON::Field(key: "documentHighlightProvider")]
    property document_highlight_provider : (Bool | DocumentHighlightOptions)?

    # The server provides document symbol support.
    @[JSON::Field(key: "documentSymbolProvider")]
    property document_symbol_provider : (Bool | DocumentSymbolOptions)?

    # The server provides code actions. The `CodeActionOptions` return type is only
    # valid if the client signals code action literal support via the property
    # `textDocument.codeAction.codeActionLiteralSupport`.
    @[JSON::Field(key: "codeActionProvider")]
    property code_action_provider : (Bool | CodeActionOptions)?

    # The server provides code lens.
    @[JSON::Field(key: "codeLensProvider")]
    property code_lens_provider : CodeLensOptions?

    # The server provides document link support.
    @[JSON::Field(key: "documentLinkProvider")]
    property document_link_provider : DocumentLinkOptions?

    # The server provides color provider support.
    @[JSON::Field(key: "colorProvider")]
    property color_provider : (Bool | DocumentColorOptions | DocumentColorRegistrationOptions)?

    # The server provides document formatting.
    @[JSON::Field(key: "documentFormattingProvider")]
    property document_formatting_provider : (Bool | DocumentFormattingOptions)?

    # The server provides document range formatting.
    @[JSON::Field(key: "documentRangeFormattingProvider")]
    property document_range_formatting_provider : (Bool | DocumentRangeFormattingOptions)?

    # The server provides document formatting on typing.
    @[JSON::Field(key: "documentOnTypeFormattingProvider")]
    property document_on_type_formatting_provider : DocumentOnTypeFormattingOptions?

    # The server provides rename support. RenameOptions may only be
    # specified if the client states that it supports
    # `prepareSupport` in its initial `initialize` request.
    @[JSON::Field(key: "renameProvider")]
    property rename_provider : (Bool | RenameOptions)?

    # The server provides folding provider support.
    @[JSON::Field(key: "foldingRangeProvider")]
    property folding_range_provider : (Bool | FoldingRangeOptions | FoldingRangeRegistrationOptions)?

    # The server provides execute command support.
    @[JSON::Field(key: "executeCommandProvider")]
    property execute_command_provider : ExecuteCommandOptions?

    # The server provides selection range support.
    @[JSON::Field(key: "selectionRangeProvider")]
    property selection_range_provider : (Bool | SelectionRangeOptions | SelectionRangeRegistrationOptions)?

    # The server provides workspace symbol support.
    @[JSON::Field(key: "workspaceSymbolProvider")]
    property workspace_symbol_provider : Bool?

    # Workspace specific server capabilities
    @[JSON::Field(key: "workspace")]
    property workspace : WorkspaceValue?

    # Experimental server capabilities.
    @[JSON::Field(key: "experimental")]
    property experimental : JSON::Any?
  end

  # Defines how the host (editor) should sync document changes to the language server.
  enum TextDocumentSyncKind
    # Documents should not be synced at all.
    None = 0
    # Documents are synced by always sending the full content
    # of the document.
    Full = 1
    # Documents are synced by sending the full content on open.
    # After that only incremental updates to the document are
    # send.
    Incremental = 2
  end

  struct TextDocumentSyncOptions
    include Initializer
    include JSON::Serializable

    # Open and close notifications are sent to the server. If omitted open close notification should not
    # be sent.
    @[JSON::Field(key: "openClose")]
    property open_close : Bool?

    # Change notifications are sent to the server. See TextDocumentSyncKind.None, TextDocumentSyncKind.Full
    # and TextDocumentSyncKind.Incremental. If omitted it defaults to TextDocumentSyncKind.None.
    property change : TextDocumentSyncKind?
  end

  # Completion options.
  struct CompletionOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # Most tools trigger completion request automatically without explicitly requesting
    # it using a keyboard shortcut (e.g. Ctrl+Space). Typically they do so when the user
    # starts to type an identifier. For example if the user types `c` in a JavaScript file
    # code complete will automatically pop up present `console` besides others as a
    # completion item. Characters that make up identifiers don't need to be listed here.
    #
    # If code complete should automatically be trigger on characters not being valid inside
    # an identifier (for example `.` in JavaScript) list them in `triggerCharacters`.
    @[JSON::Field(key: "triggerCharacters")]
    property trigger_characters : Array(String)?

    # The list of all possible characters that commit a completion. This field can be used
    # if clients don't support individual commit characters per completion item. See
    # `ClientCapabilities.textDocument.completion.completionItem.commitCharactersSupport`.
    #
    # If a server provides both `allCommitCharacters` and commit characters on an individual
    # completion item the ones on the completion item win.
    @[JSON::Field(key: "allCommitCharacters")]
    property all_commit_characters : Array(String)?

    # The server provides support to resolve additional
    # information for a completion item.
    @[JSON::Field(key: "resolveProvider")]
    property resolve_provider : Bool?
  end

  struct HoverOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct SignatureHelpOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # The characters that trigger signature help automatically.
    @[JSON::Field(key: "triggerCharacters")]
    property trigger_characters : Array(String)?

    # List of characters that re-trigger signature help.
    #
    # These trigger characters are only active when signature help is already showing. All trigger characters
    # are also counted as re-trigger characters.
    @[JSON::Field(key: "retriggerCharacters")]
    property retrigger_characters : Array(String)?
  end

  struct DeclarationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct DeclarationRegistrationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
    include TextDocumentRegistrationOptions
    include StaticRegistrationOptions
  end

  struct DefinitionOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct TypeDefinitionOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct TypeDefinitionRegistrationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
    include TextDocumentRegistrationOptions
    include StaticRegistrationOptions
  end

  struct ImplementationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct ImplementationRegistrationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
    include TextDocumentRegistrationOptions
    include StaticRegistrationOptions
  end

  struct ReferenceOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct DocumentHighlightOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct DocumentSymbolOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct CodeActionOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # CodeActionKinds that this server may return.
    #
    # The list of kinds may be generic, such as `CodeActionKind.Refactor`, or the server
    # may list out every specific kind they provide.
    @[JSON::Field(key: "codeActionKinds")]
    property code_action_kinds : Array(CodeActionKind)?
  end

  struct CodeLensOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # Code lens has a resolve provider as well.
    @[JSON::Field(key: "resolveProvider")]
    property resolve_provider : Bool?
  end

  struct DocumentLinkOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # Document links have a resolve provider as well.
    @[JSON::Field(key: "resolveProvider")]
    property resolve_provider : Bool?
  end

  struct DocumentColorOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct DocumentColorRegistrationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
    include TextDocumentRegistrationOptions
    include StaticRegistrationOptions
  end

  struct DocumentFormattingOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct DocumentRangeFormattingOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct DocumentOnTypeFormattingOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # A character on which formatting should be triggered, like `}`.
    @[JSON::Field(key: "firstTriggerCharacter")]
    property first_trigger_character : String

    # More trigger characters.
    @[JSON::Field(key: "moreTriggerCharacter")]
    property more_trigger_character : Array(String)?
  end

  struct RenameOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # Renames should be checked and tested before being executed.
    @[JSON::Field(key: "prepareProvider")]
    property prepare_provider : Bool?
  end

  struct FoldingRangeOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct FoldingRangeRegistrationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
    include TextDocumentRegistrationOptions
    include StaticRegistrationOptions
  end

  struct ExecuteCommandOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions

    # The commands to be executed on the server
    property commands : Array(String)
  end

  struct SelectionRangeOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
  end

  struct SelectionRangeRegistrationOptions
    include Initializer
    include JSON::Serializable
    include WorkDoneProgressOptions
    include TextDocumentRegistrationOptions
    include StaticRegistrationOptions
  end

  struct WorkspaceValue
    include Initializer
    include JSON::Serializable

    # The server supports workspace folder.
    @[JSON::Field(key: "workspaceFolders")]
    property workspace_folders : WorkspaceFoldersServerCapabilities
  end
end
