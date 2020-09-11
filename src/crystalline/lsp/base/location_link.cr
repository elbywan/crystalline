require "json"
require "./range"
require "../tools"

# Represents a location inside a resource, such as a line inside a text file.
class LSP::LocationLink
  include JSON::Serializable
  include Initializer

  # Span of the origin of this link.
  #
  # Used as the underlined span for mouse interaction. Defaults to the word range at
  # the mouse position.
  @[JSON::Field(key: "originSelectionRange")]
  property origin_selection_range : Range?

  # The target resource identifier of this link.
  @[JSON::Field(key: "targetUri")]
  property target_uri : String

  # The full target range of this link. If the target for example is a symbol then target range is the
  # range enclosing this symbol not including leading/trailing whitespace but everything else
  # like comments. This information is typically used to highlight the range in the editor.
  @[JSON::Field(key: "targetRange")]
  property target_range : Range

  # The range that should be selected and revealed when this link is being followed, e.g the name of a function.
  # Must be contained by the the `targetRange`. See also `DocumentSymbol#range`
  @[JSON::Field(key: "targetSelectionRange")]
  property target_selection_range : Range
end
