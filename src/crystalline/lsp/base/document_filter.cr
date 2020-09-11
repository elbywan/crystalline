require "json"
require "../tools"
require "./text_document_identifier"
require "./position"

module LSP
  # A document selector is the combination of one or more document filters.
  alias DocumentSelector = Array(DocumentFilter)
end

# A document filter denotes a document through properties like language, scheme or pattern.
#
# An example is a filter that applies to TypeScript files on disk.
# Another example is a filter the applies to JSON files with name package.json:
#
# ```
# { language: 'typescript', scheme: 'file' }
# { language: 'json', pattern: '**/package.json' }
# ```
class LSP::DocumentFilter
  include JSON::Serializable
  include Initializer

  # A language id, like `typescript`.
  property language : String?

  # A Uri [scheme](#Uri.scheme), like `file` or `untitled`.
  property scheme : String?

  # A glob pattern, like `*.{ts,js}`.
  #
  # Glob patterns can have the following syntax:
  # - `*` to match one or more characters in a path segment
  # - `?` to match on one character in a path segment
  # - `**` to match any number of path segments, including none
  # - `{}` to group conditions (e.g. `**​/*.{ts,js}` matches all TypeScript and JavaScript files)
  # - `[]` to declare a range of characters to match in a path segment (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
  # - `[!...]` to negate a range of characters to match in a path segment (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not `example.0`)
  property pattern : String?
end
