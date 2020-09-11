require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The Completion request is sent from the client to the server to compute completion items at a given cursor position.
    #
    # Completion items are presented in the [IntelliSense](https://code.visualstudio.com/docs/editor/intellisense).
    class CompletionRequest < RequestMessage((Array(CompletionItem) | CompletionList)?)
      @method = "textDocument/completion"
      property params : CompletionParams
    end
  end

  struct CompletionParams
    include TextDocumentPositionParams
    include WorkDoneProgressParams
    include PartialResultParams
    include Initializer
    include JSON::Serializable

    # The completion context. This is only available if the client specifies
    # to send this using `ClientCapabilities.textDocument.completion.contextSupport === true`
    property context : CompletionContext?
  end

  # How a completion was triggered
  enum CompletionTriggerKind
    # Completion was triggered by typing an identifier (24x7 code
    # complete), manual invocation (e.g Ctrl+Space) or via API.
    Invoked = 1

    # Completion was triggered by a trigger character specified by
    # the `triggerCharacters` properties of the `CompletionRegistrationOptions`.
    TriggerCharacter = 2

    # Completion was re-triggered as the current completion list is incomplete.
    TriggerForIncompleteCompletions = 2
  end

  # Contains additional information about the context in which a completion request is triggered.
  struct CompletionContext
    include Initializer
    include JSON::Serializable

    # How the completion was triggered.
    @[JSON::Field(key: "triggerKind")]
    property trigger_kind : CompletionTriggerKind

    # The trigger character (a single character) that has trigger code complete.
    # Is undefined if `triggerKind !== CompletionTriggerKind.TriggerCharacter`
    @[JSON::Field(key: "triggerCharacter")]
    property trigger_character : String?
  end
end
