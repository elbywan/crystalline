require "json"
require "../tools"
require "./text_edit"
require "./markup_content"
require "./command"

module LSP
  # The kind of a completion entry.
  enum CompletionItemKind
    Text          =  1
    Method        =  2
    Function      =  3
    Constructor   =  4
    Field         =  5
    Variable      =  6
    Class         =  7
    Interface     =  8
    Module        =  9
    Property      = 10
    Unit          = 11
    Value         = 12
    Enum          = 13
    Keyword       = 14
    Snippet       = 15
    Color         = 16
    File          = 17
    Reference     = 18
    Folder        = 19
    EnumMember    = 20
    Constant      = 21
    Struct        = 22
    Event         = 23
    Operator      = 24
    TypeParameter = 25
  end

  # Completion item tags are extra annotations that tweak the rendering of a completion
  # item.
  enum CompletionItemTag
    # Render a completion as obsolete, usually using a strike-out.
    Deprecated = 1
  end

  # Defines whether the insert text in a completion item should be interpreted as
  # plain text or a snippet.
  enum InsertTextFormat
    # The primary text to be inserted is treated as a plain string.
    PlainText = 1
    # The primary text to be inserted is treated as a snippet.
    #
    # A snippet can define tab stops and placeholders with `$1`, `$2`
    # and `${3:foo}`. `$0` defines the final tab stop, it defaults to
    # the end of the snippet. Placeholders with equal identifiers are linked,
    # that is typing in one will update others too.
    Snippet = 2
  end

  struct CompletionItem
    include Initializer
    include JSON::Serializable

    # The label of this completion item. By default
    # also the text that is inserted when selecting
    # this completion.
    property label : String

    # The kind of this completion item. Based of the kind
    # an icon is chosen by the editor. The standardized set
    # of available values is defined in `CompletionItemKind`.
    property kind : CompletionItemKind?

    # Tags for this completion item.
    property tags : Array(CompletionItemTag)?

    # A human-readable string with additional information
    # about this item, like type or symbol information.
    property detail : String?

    # A human-readable string that represents a doc-comment.
    property documentation : (String | MarkupContent)?

    # Select this item when showing.
    # *Note* that only one completion item can be selected and that the
    # tool / client decides which item that is. The rule is that the *first*
    # item of those that match best is selected.
    property preselect : Bool?

    # A string that should be used when comparing this item
    # with other items. When `falsy` the label is used.
    @[JSON::Field(key: "sortText")]
    property sort_text : String?

    # A string that should be used when filtering a set of
    # completion items. When `falsy` the label is used.
    @[JSON::Field(key: "filterText")]
    property filter_text : String?

    # A string that should be inserted into a document when selecting
    # this completion. When `falsy` the label is used.
    #
    # The `insertText` is subject to interpretation by the client side.
    # Some tools might not take the string literally. For example
    # VS Code when code complete is requested in this example `con<cursor position>`
    # and a completion item with an `insertText` of `console` is provided it
    # will only insert `sole`. Therefore it is recommended to use `textEdit` instead
    # since it avoids additional client side interpretation.
    @[JSON::Field(key: "insertText")]
    property insert_text : String?

    # The format of the insert text. The format applies to both the `insertText` property
    # and the `newText` property of a provided `textEdit`. If omitted defaults to
    # `InsertTextFormat.PlainText`.
    @[JSON::Field(key: "insertTextFormat")]
    property insert_text_format : InsertTextFormat?

    # An edit which is applied to a document when selecting this completion. When an edit is provided the value of
    # `insertText` is ignored.
    #
    # *Note:* The range of the edit must be a single line range and it must contain the position at which completion
    # has been requested.
    @[JSON::Field(key: "textEdit")]
    property text_edit : TextEdit?

    # An optional array of additional text edits that are applied when
    # selecting this completion. Edits must not overlap (including the same insert position)
    # with the main edit nor with themselves.
    #
    # Additional text edits should be used to change text unrelated to the current cursor position
    # (for example adding an import statement at the top of the file if the completion item will
    # insert an unqualified type).
    @[JSON::Field(key: "additionalTextEdits")]
    property additional_text_edits : Array(TextEdit)?

    # An optional set of characters that when pressed while this completion is active will accept it first and
    # then type that character. *Note* that all commit characters should have `length=1` and that superfluous
    # characters will be ignored.
    @[JSON::Field(key: "commitCharacters")]
    property commit_characters : Array(String)?

    # An optional command that is executed *after* inserting this completion. *Note* that
    # additional modifications to the current document should be described with the
    # additionalTextEdits-property.
    property command : Command?

    property data : JSON::Any?
  end
end
