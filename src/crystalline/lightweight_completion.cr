require "lsp/server"
require "./completion_context"
require "./lightweight_inference"
require "./lightweight_query"

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
      if type_name?(receiver)
        return {[receiver], true} if @query.find_type(receiver)
        return {[] of String, true}
      end

      return {[] of String, false} unless local_name?(receiver)

      inference = Inference.for(
        @source,
        @line_number + 1,
        @context.analysis_column + 1,
        @query,
      )

      return {[] of String, false} unless inference

      {
        inference.types_for(receiver).select { |type_name| @query.find_type(type_name) != nil },
        false,
      }
    end

    private def receiver_expression : String
      prefix = @context.analysis_prefix
      start = prefix.size

      while start > 0 && receiver_char?(prefix[start - 1])
        start -= 1
      end

      prefix[start..]? || ""
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

    private def receiver_char?(char : Char)
      char.ascii_alphanumeric? || char.in?('_', '?', '!', '@', ':')
    end

    private def local_name?(receiver : String)
      !!(receiver =~ /\A[a-z_][a-zA-Z0-9_?!]*\z/)
    end

    private def type_name?(receiver : String)
      !!(receiver =~ /\A[A-Z][a-zA-Z0-9_]*(?:::[A-Z][a-zA-Z0-9_]*)*\z/)
    end
  end
end
