require "json"
require "../tools"

module LSP
  struct WorkspaceFolder
    include Initializer
    include JSON::Serializable

    property uri : String
    property name : String
  end
end
