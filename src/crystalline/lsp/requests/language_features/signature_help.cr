require "json"
require "../../tools"
require "../../base/*"
require "../request_message"

module LSP
  macro finished
    # The signature help request is sent from the client to the server to request signature information at a given cursor position.
    class SignatureHelpRequest < RequestMessage(SignatureHelp?)
      @method = "textDocument/signatureHelp"
      property params : SignatureHelpParams
    end
  end

  struct SignatureHelpParams
    include TextDocumentPositionParams
    include WorkDoneProgressParams
    include Initializer
    include JSON::Serializable

    # The signature help context. This is only available if the client specifies
    # to send this using the client capability  `textDocument.signatureHelp.contextSupport === true`
    property context : SignatureHelpContext?
  end

  # How a signature help was triggered.
  enum SignatureHelpTriggerKind
    # Signature help was invoked manually by the user or by a command.
    Invoked = 1
    # Signature help was triggered by a trigger character.
    TriggerCharacter = 2
    # Signature help was triggered by the cursor moving or by the document content changing.
    ContentChange = 3
  end

  # Additional information about the context in which a signature help request was triggered.
  struct SignatureHelpContext
    include Initializer
    include JSON::Serializable

    # Action that caused signature help to be triggered.
    @[JSON::Field(key: "triggerKind")]
    property trigger_kind : SignatureHelpTriggerKind

    # Character that caused signature help to be triggered.
    #
    # This is undefined when `triggerKind !== SignatureHelpTriggerKind.TriggerCharacter`
    @[JSON::Field(key: "triggerCharacter")]
    property trigger_character : String?

    # `true` if signature help was already showing when it was triggered.
    #
    # Retriggers occur when the signature help is already active and can be caused by actions such as
    # typing a trigger character, a cursor move, or document content changes.
    @[JSON::Field(key: "isRetrigger")]
    property is_retrigger : Bool

    # The currently active `SignatureHelp`.
    #
    # The `activeSignatureHelp` has its `SignatureHelp.activeSignature` field updated based on
    # the user navigating through available signatures.
    @[JSON::Field(key: "activeSignatureHelp")]
    property active_signature_help : SignatureHelp?
  end

  # Signature help represents the signature of something
  # callable. There can be multiple signature but only one
  # active and only one active parameter.
  struct SignatureHelp
    include Initializer
    include JSON::Serializable

    # One or more signatures. If no signaures are availabe the signature help
    # request should return `null`.
    @[JSON::Field(key: "signatures")]
    property signatures : Array(SignatureInformation)

    # The active signature. If omitted or the value lies outside the
    # range of `signatures` the value defaults to zero or is ignore if
    # the `SignatureHelp` as no signatures.
    #
    # Whenever possible implementors should make an active decision about
    # the active signature and shouldn't rely on a default value.
    #
    # In future version of the protocol this property might become
    # mandatory to better express this.
    @[JSON::Field(key: "activeSignature")]
    property active_signature : Int32?

    # The active parameter of the active signature. If omitted or the value
    # lies outside the range of `signatures[activeSignature].parameters`
    # defaults to 0 if the active signature has parameters. If
    # the active signature has no parameters it is ignored.
    # In future version of the protocol this property might become
    # mandatory to better express the active parameter if the
    # active signature does have any.
    @[JSON::Field(key: "activeParameter")]
    property active_parameter : Int32?
  end

  # Represents the signature of something callable. A signature
  # can have a label, like a function-name, a doc-comment, and
  # a set of parameters.
  struct SignatureInformation
    include Initializer
    include JSON::Serializable

    # The label of this signature. Will be shown in
    # the UI.
    property label : String

    # The human-readable doc-comment of this signature. Will be shown
    # in the UI but can be omitted.
    property documentation : (String | MarkupContent)?

    # The parameters of this signature.
    property parameters : Array(ParameterInformation)?
  end

  # Represents a parameter of a callable-signature. A parameter can
  # have a label and a doc-comment.
  struct ParameterInformation
    include Initializer
    include JSON::Serializable

    # The label of this parameter information.
    #
    # Either a string or an inclusive start and exclusive end offsets within its containing
    # signature label. (see SignatureInformation.label). The offsets are based on a UTF-16
    # string representation as `Position` and `Range` does.
    #
    # *Note*: a label of type string should be a substring of its containing signature label.
    # Its intended use case is to highlight the parameter label part in the `SignatureInformation.label`.
    property label : String | {Int32, Int32}

    # The human-readable doc-comment of this parameter. Will be shown
    # in the UI but can be omitted.
    property documentation : (String | MarkupContent)?
  end
end
