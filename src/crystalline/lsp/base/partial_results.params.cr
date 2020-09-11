require "json"
require "../tools"
require "../notifications/progress"

module LSP::PartialResultParams
  include JSON::Serializable
  include Initializer

  # An optional token that a server can use to report partial results (e.g. streaming) to
  # the client.
  @[JSON::Field(key: "partialResultToken")]
  property partial_result_token : ProgressToken?
end
