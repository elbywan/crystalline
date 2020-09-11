require "json"
require "../../tools"

struct LSP::DidChangeWatchedFilesClientCapabilities
  include JSON::Serializable
  include Initializer

  # Did change watched files notification supports dynamic registration. Please note
  # that the current protocol doesn't support static configuration for file changes
  # from the server side.
  @[JSON::Field(key: "dynamicRegistration")]
  property dynamic_registration : Bool?
end
