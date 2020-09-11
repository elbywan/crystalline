require "json"
require "./range"
require "./location"
require "../tools"

module LSP
  enum DiagnosticSeverity
    Error       = 1
    Warning     = 2
    Information = 3
    Hint        = 4
  end

  enum DiagnosticTag
    # Unused or unnecessary code.
    #
    # Clients are allowed to render diagnostics with this tag faded out instead of having
    # an error squiggle.
    Unnecessary = 1
    # Deprecated or obsolete code.
    #
    # Clients are allowed to rendered diagnostics with this tag strike through.
    Deprecated = 2
  end

  # Represents a related message and source code location for a diagnostic. This should be
  # used to point to code locations that cause or are related to a diagnostics, e.g when duplicating
  # a symbol in a scope.
  class DiagnosticRelatedInformation
    include Initializer
    include JSON::Serializable

    # The location of this related diagnostic information.
    property location : Location
    # The message of this related diagnostic information.
    property message : String
  end

  # Represents a diagnostic, such as a compiler error or warning.
  # Diagnostic objects are only valid in the scope of a resource.
  # See: https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#diagnostic
  class Diagnostic
    include Initializer
    include JSON::Serializable

    # The range at which the message applies.
    property range : Range
    # The diagnostic's severity. Can be omitted. If omitted it is up to the
    # client to interpret diagnostics as error, warning, info or hint.
    property severity : Int32?
    # The diagnostic's code, which might appear in the user interface.
    property code : (Int32 | String)?
    # A human-readable string describing the source of this
    # diagnostic, e.g. 'typescript' or 'super lint'.
    property source : String?
    # The diagnostic's message.
    property message : String
    # Additional metadata about the diagnostic.
    property tags : Array(DiagnosticTag)?

    # An array of related diagnostic information, e.g. when symbol-names within
    # a scope collide all definitions can be marked via this property.
    @[JSON::Field(key: "relatedInformation")]
    property related_information : Array(DiagnosticRelatedInformation)?

    def initialize(line : Int32?, column : Int32?, size : Int32?, @message, @source)
      line = line || 0
      size = size || 1
      @range = Range.new({
        start: Position.new({line: line - 1, character: column - 1}),
        end:   Position.new({line: line - 1, character: column + size - 1}),
      })
      @severity = DiagnosticSeverity::Error.value
    end
  end
end
