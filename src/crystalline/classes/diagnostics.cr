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

  def append_from_exception(error : Crystal::ErrorFormat)
    bottom_error : Crystal::ErrorFormat = error

    loop do
      if error.is_a? Crystal::ErrorFormat
        bottom_error = error
      end
      if error.responds_to? :inner
        break unless (error = error.inner)
      else
        break
      end
    end

    bottom_error.tap { |err|
      err = err.as(Crystal::ErrorFormat)
      if err.filename.is_a? Crystal::VirtualFile && (expanded_source = err.filename.as(Crystal::VirtualFile).expanded_location)
        line = expanded_source.line_number || 1
        column = expanded_source.column_number
      else
        line = err.line_number || 1
        column = err.column_number
      end
      self.append(LSP::Diagnostic.new(
        line: line,
        column: column,
        size: err.size || 0,
        message: err.message || "Unknown error.",
        source: err.true_filename
      ))
    }
  end

  def publish(server : LSP::Server)
    @diagnostics.each { |key, value|
      server.try &.send(LSP::PublishDiagnosticsNotification.new(
        params: LSP::PublishDiagnosticsParams.new(uri: key, diagnostics: value),
      ))
    }
  end
end
