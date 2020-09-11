require "json"
require "../tools"
require "../ext/enum"

# The kind of a code action.
#
# Kinds are a hierarchical list of identifiers separated by `.`, e.g. `"refactor.extract.function"`.
#
# The set of kinds is open and client needs to announce the kinds it supports to the server during
# initialization.
Enum.string CodeActionKind, mappings: {
  Empty:                 "",
  RefactorExtract:       "refactor.extract",
  RefactorInline:        "refactor.inline",
  RefactorRewrite:       "refactor.rewrite",
  SourceOrganizeImports: "source.organizeImports",
} do
  # Empty kind.
  Empty
  # Base kind for quickfix actions: 'quickfix'.
  QuickFix
  # Base kind for refactoring actions: 'refactor'.
  Refactor
  # Base kind for refactoring extraction actions: 'refactor.extract'.
  #
  #
  # Example extract actions:
  #
  # - Extract method
  # - Extract function
  # - Extract variable
  # - Extract interface from class
  # - ...
  RefactorExtract
  # Base kind for refactoring inline actions: 'refactor.inline'.
  #
  # Example inline actions:
  #
  # - Inline function
  # - Inline variable
  # - Inline constant
  # - ...
  RefactorInline
  # Base kind for refactoring rewrite actions: 'refactor.rewrite'.
  #
  # Example rewrite actions:
  #
  # - Convert JavaScript function to class
  # - Add or remove parameter
  # - Encapsulate field
  # - Make method static
  # - Move method to base class
  # - ...
  #
  RefactorRewrite
  # Base kind for source actions: `source`.
  #
  # Source code actions apply to the entire file.
  Source
  # Base kind for an organize imports source action: `source.organizeImports`.
  SourceOrganizeImports
end
