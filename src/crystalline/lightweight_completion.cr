require "lsp/server"
require "./completion_context"
require "./lightweight_query"
require "./lightweight_resolver"

module Crystalline::Lightweight
  class Completion
    def self.complete(source : String, line_number : Int32, context : Crystalline::CompletionContext, query : Query) : Array(LSP::CompletionItem)?
      return unless context.trigger_character == "."

      new(source, line_number, context, query).complete
    end

    def initialize(@source : String, @line_number : Int32, @context : Crystalline::CompletionContext, @query : Query)
    end

    def complete : Array(LSP::CompletionItem)?
      receiver = receiver_expression
      return if receiver.empty?

      type_names, class_method = resolve_receiver(receiver)
      return if type_names.empty?

      range = @context.completion_range(@line_number)
      items = [] of LSP::CompletionItem
      seen = Set(String).new

      type_names.each do |type_name|
        @query.methods_for(type_name, class_method: class_method).each do |method|
          key = "#{method.owner}:#{method.class_method}:#{method.name}"
          next if seen.includes?(key)
          seen << key

          items << LSP::CompletionItem.new(
            label: format_method(method),
            insert_text: method.name,
            filter_text: method.name,
            detail: format_method(method, include_owner: true),
            kind: method.class_method ? LSP::CompletionItemKind::Function : LSP::CompletionItemKind::Method,
            sort_text: method.name,
            text_edit: LSP::TextEdit.new(
              range: range,
              new_text: method.name,
            ),
            documentation: method.doc.try { |doc|
              LSP::MarkupContent.new(
                kind: LSP::MarkupKind::MarkDown,
                value: doc,
              )
            },
          )
        end
      end

      items
    end

    private def resolve_receiver(receiver : String) : {Array(String), Bool}
      Resolver.receiver_types(@source, @line_number, @context.analysis_column, receiver, @query)
    end

    private def receiver_expression : String
      Resolver.receiver_from_prefix(@context.analysis_prefix)
    end

    private def format_method(method : MethodInfo, *, include_owner = false) : String
      args = method.args.map do |arg|
        if restriction = arg.restriction
          "#{arg.name} : #{restriction}"
        else
          arg.name
        end
      end.join(", ")

      signature = String.build do |str|
        if include_owner
          str << method.owner
          str << (method.class_method ? "." : "#")
        end

        str << method.name
        str << "(#{args})"
        str << " : #{method.return_type}" if method.return_type
      end

      signature
    end

  end
end
