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

  def init_value(key : String) : self
    unless @diagnostics.has_key?(key)
      @diagnostics[key] = [] of LSP::Diagnostic
    end
    self
  end

  def append_from_exception(error : Crystal::ErrorFormat)
    error_stack = Deque(Crystal::ErrorFormat).new

    loop do
      error_stack << error if error.is_a? Crystal::ErrorFormat
      if error.responds_to? :inner
        break unless (error = error.inner)
      else
        break
      end
    end

    related_information = [] of LSP::DiagnosticRelatedInformation

    error_stack.each_with_index { |err, i|
      bottom_error = i == error_stack.size - 1
      if err.filename.is_a? Crystal::VirtualFile && (expanded_source = err.filename.as(Crystal::VirtualFile).expanded_location)
        line = expanded_source.line_number || 1
        column = expanded_source.column_number
      else
        line = err.line_number || 1
        column = err.column_number
      end

      if bottom_error
        self.append(LSP::Diagnostic.new(
          line: line,
          column: column,
          size: err.size || 0,
          message: err.message || "Unknown error.",
          source: err.true_filename,
          related_information: related_information.reverse
        ))
      else
        related_information << LSP::DiagnosticRelatedInformation.new(
          line: line,
          column: column,
          size: err.size || 0,
          message: err.message || "Unknown error.",
          filename: err.true_filename,
        )
      end
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
