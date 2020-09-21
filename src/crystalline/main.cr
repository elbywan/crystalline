require "log"
require "./ext/*"
require "./lsp/server"
require "./*"

module Crystalline
  VERSION = "0.1.0"

  SERVER_CAPABILITIES = LSP::ServerCapabilities.new({
    text_document_sync:                 LSP::TextDocumentSyncKind::Incremental,
    document_formatting_provider:       true,
    document_range_formatting_provider: true,
    completion_provider:                LSP::CompletionOptions.new({
      trigger_characters: [".", ":"],
    }),
    hover_provider:          true,
    definition_provider:     true,
    # signature_help_provider: LSP::SignatureHelpOptions.new({
    #   trigger_characters: ["(", " "]
    # }),
  })

  module EnvironmentConfig
    def self.run
      initialize_from_crystal_env.each do |k, v|
        ENV[k] = v
      end
    end

    private def self.initialize_from_crystal_env
      crystal_env
        .lines
        .map(&.split('='))
        .to_h
    end

    private def self.crystal_env
      String.build do |io|
        Process.run("crystal", ["env"], output: io)
      end
    end
  end

  def self.init(*, input : IO = STDIN, output : IO = STDOUT)
    EnvironmentConfig.run
    server = LSP::Server.new(input, output, SERVER_CAPABILITIES)
    Controller.new(server)
  rescue ex
    LSP::Log.error(exception: ex) { %(#{ex.message || "Unknown error during init."}\n#{ex.backtrace.join('\n')}) }
  end
end
