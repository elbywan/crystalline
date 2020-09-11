require "json"
require "../tools"

class LSP::Position
  include JSON::Serializable
  include Initializer

  # Line position in a document (zero-based).
  property line : Int32
  # Character offset on a line in a document (zero-based). Assuming that the line is
  # represented as a string, the `character` value represents the gap between the
  # `character` and `character + 1`.
  #
  # If the character value is greater than the line length it defaults back to the
  # line length.
  property character : Int32
end
