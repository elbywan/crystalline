require "lsp/server"

# The set of code action kinds is open and hierarchical: clients may announce
# custom kinds or sub-kinds such as `source.fixAll` (Vim does), and the LSP
# specification requires servers to handle values outside the announced set
# gracefully.
#
# The shard builds its enum parsers from `Enum.string`, which raises on unknown
# values while deserializing the client capabilities. That aborts the whole
# initialize handshake, so unknown kinds resolve to their announced parent kind
# (`source.fixAll` -> `source`) and custom kinds to `Empty`. Crystalline does
# not implement code actions, the announced kinds only matter to servers that
# filter the actions they offer.
enum LSP::CodeActionKind
  def self.parse(string : String) : self
    previous_def
  rescue ArgumentError
    dot = string.rindex('.')
    dot ? parse(string[...dot]) : Empty
  end
end
