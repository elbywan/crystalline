require "json"
require "../tools"

# Static registration options can be used to register a feature in the initialize result
# with a given server control ID to be able to un-register the feature later on.
module LSP::StaticRegistrationOptions
  # The id used to register the request. The id can be used to deregister
  # the request again. See also Registration#id.
  property id : String?
end
