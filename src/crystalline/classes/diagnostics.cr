require "../lsp/base/diagnostic"

class Crystalline::Diagnostics
  alias DiagnosticsHash = Hash(String, Array(LSP::Diagnostic))

  @diagnostics : DiagnosticsHash = {} of String => Array(LSP::Diagnostic)
  forward_missing_to(@diagnostics)

  def append(diagnostic : LSP::Diagnostic)
    key = "file://#{diagnostic.source}"
    self.init_value(key)
    @diagnostics[key] << diagnostic
  end

  def init_value(key : String)
    unless @diagnostics.has_key?(key)
      @diagnostics[key] = [] of LSP::Diagnostic
    end
  end

  def append_from_exception(error : Crystal::TypeException | Crystal::SyntaxException)
    loop do
      if error.is_a? Crystal::ErrorFormat
        self.append(LSP::Diagnostic.new(
          line: error.line_number || 1,
          column: error.column_number,
          size: error.size || 0,
          message: error.message || "Unknown error.",
          source: error.true_filename
        ))
        if error.responds_to? :inner
          break unless (error = error.inner)
        else
          break
        end
      else
        break
      end
    end
  end

  def publish(server : LSP::Server)
    @diagnostics.each { |key, value|
      server.try &.send(LSP::PublishDiagnosticsNotification.new({
        params: LSP::PublishDiagnosticsParams.new({uri: key, diagnostics: value}),
      }))
    }
  end
end
