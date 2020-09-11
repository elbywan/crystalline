require "json"
require "../../tools"

struct LSP::DidChangeConfigurationClientCapabilities
  include JSON::Serializable
  include Initializer

  # Did change configuration notification supports dynamic registration.
  @[JSON::Field(key: "dynamicRegistration")]
  property dynamic_registration : Bool?
end
