require "json"
require "./position"
require "../tools"

class LSP::Range
  include JSON::Serializable
  include Initializer

  # The range's start position.
  property start : Position

  # The range's end position.
  property end : Position
end
