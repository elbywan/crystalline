require "json"
require "../../tools"

struct LSP::ExecuteCommandClientCapabilities
  include JSON::Serializable
  include Initializer

  # Execute command supports dynamic registration.
  @[JSON::Field(key: "dynamicRegistration")]
  property dynamic_registration : Bool?
end
