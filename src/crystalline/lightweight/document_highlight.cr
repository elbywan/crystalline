require "lsp/server"
require "./occurrences"

module Crystalline::Lightweight
  # Highlights the occurrences of the symbol at a position.
  #
  # Only local variables, parameters and block arguments are resolved (see
  # `Occurrences`): the lightweight engine has no reference index for methods,
  # types and instance variables, and name matching would highlight unrelated
  # symbols.
  class DocumentHighlight
    def self.highlights(source : String, line_number : Int32, column_number : Int32) : Array(LSP::DocumentHighlight)?
      occurrences = Occurrences.at(source, line_number, column_number)
      return unless occurrences

      occurrences.occurrences.map do |occurrence|
        LSP::DocumentHighlight.new(
          range: occurrence.range,
          kind: occurrence.write ? LSP::DocumentHighlightKind::Write : LSP::DocumentHighlightKind::Read,
        )
      end
    end
  end
end
