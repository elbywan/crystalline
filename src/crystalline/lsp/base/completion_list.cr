require "json"
require "../tools"
require "./completion_item"

module LSP
  # Represents a collection of [completion items](#CompletionItem) to be presented
  # in the editor.
  struct CompletionList
    include Initializer
    include JSON::Serializable

    # This list it not complete. Further typing should result in recomputing
    # this list.
    @[JSON::Field(key: "isIncomplete")]
    property is_incomplete : Bool

    # The completion items.
    property items : Array(CompletionItem)
  end
end
