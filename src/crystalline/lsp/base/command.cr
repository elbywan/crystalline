require "json"
require "../tools"

# Represents a reference to a command.
#
# Provides a title which will be used to represent a command in the UI.
# Commands are identified by a string identifier.
# The recommended way to handle commands is to implement their execution on the server side if the
# client and server provides the corresponding capabilities.
# Alternatively the tool extension code could handle the command.
# The protocol currently doesn’t specify a set of well-known commands.
class LSP::Command
  include Initializer
  include JSON::Serializable

  # Title of the command, like `save`.
  property title : String
  # The identifier of the actual command handler.
  property command : String
  # Arguments that the command handler should be
  # invoked with.
  property arguments : JSON::Any?
end
