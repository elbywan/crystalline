require "json"
require "./range"
require "../tools"

# Represents a location inside a resource, such as a line inside a text file.
class LSP::Location
  include JSON::Serializable
  include Initializer

  property uri : String
  property range : Range
end
