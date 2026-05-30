require "lsp/server"
require "../completion_context"
require "./query"
require "./resolver"

module Crystalline::Lightweight
  class Completion
    def self.complete(source : String, line_number : Int32, context : Crystalline::CompletionContext, query : Query) : Array(LSP::CompletionItem)?
      new(source, line_number, context, query).complete
    end

    def initialize(@source : String, @line_number : Int32, @context : Crystalline::CompletionContext, @query : Query)
    end

    def complete : Array(LSP::CompletionItem)?
      case @context.trigger_character
      when "."
        complete_methods
      else
        complete_context_items
      end
    end

    private def complete_methods : Array(LSP::CompletionItem)?
      receiver = receiver_expression
      return if receiver.empty?

      type_names, class_method = resolve_receiver(receiver)
      return if type_names.empty?

      items = [] of LSP::CompletionItem
      seen = Set(String).new

      type_names.each do |type_name|
        @query.methods_for(type_name, class_method: class_method).each do |method|
          key = "#{method.owner}:#{method.class_method}:#{method.name}"
          next if seen.includes?(key)
          seen << key
          items << method_completion_item(method)
        end
      end

      items
    end

    private def complete_context_items : Array(LSP::CompletionItem)?
      fragment = current_fragment
      items = [] of LSP::CompletionItem
      seen = Set(String).new

      if @context.trigger_character == "@"
        inference = Inference.for(@source, @line_number + 1, @context.analysis_column + 1, @query)
        return [] of LSP::CompletionItem unless inference

        inference.instance_var_types.each_key do |name|
          next unless name.lchop('@').starts_with?(fragment)
          next if seen.includes?(name)
          seen << name
          items << variable_completion_item(name, kind: LSP::CompletionItemKind::Field, detail: "#{name} : #{inference.types_for_instance_var(name).uniq.join(" | ")}", insert_text: name.lchop('@'))
        end

        inference.class_var_types.each_key do |name|
          next unless name.lchop("@@").starts_with?(fragment)
          next if seen.includes?(name)
          seen << name
          items << variable_completion_item(name, kind: LSP::CompletionItemKind::Field, detail: "#{name} : #{inference.types_for_class_var(name).uniq.join(" | ")}", insert_text: name.lchop("@@"))
        end

        return items
      end

      if fragment[0]?.try(&.ascii_uppercase?)
        @query.all_types.each do |type|
          next unless type.name.split("::").last.starts_with?(fragment) || type.name.starts_with?(fragment)
          next if seen.includes?(type.name)
          seen << type.name
          items << type_completion_item(type)
        end
        return items
      end

      inference = Inference.for(@source, @line_number + 1, @context.analysis_column + 1, @query)

      if fragment.empty? || "self".starts_with?(fragment)
        items << variable_completion_item("self", kind: LSP::CompletionItemKind::Variable, detail: self_completion_detail(inference), insert_text: "self")
        seen << "self"
      end

      if inference
        inference.local_types.each do |name, type_names|
          next unless name.starts_with?(fragment)
          next if seen.includes?(name)
          seen << name
          items << variable_completion_item(name, detail: "#{name} : #{type_names.uniq.join(" | ")}")
        end
      end

      @query.top_level_methods.each do |method|
        next unless method.name.starts_with?(fragment)
        next if seen.includes?(method.name)
        seen << method.name
        items << method_completion_item(method)
      end

      items
    end

    private def resolve_receiver(receiver : String) : {Array(String), Bool}
      Resolver.receiver_types(@source, @line_number, @context.analysis_column, receiver, @query)
    end

    private def receiver_expression : String
      Resolver.receiver_from_prefix(@context.analysis_prefix)
    end

    private def method_completion_item(method : MethodInfo) : LSP::CompletionItem
      LSP::CompletionItem.new(
        label: format_method(method),
        insert_text: method.name,
        filter_text: method.name,
        detail: format_method(method, include_owner: true),
        kind: method.class_method ? LSP::CompletionItemKind::Function : LSP::CompletionItemKind::Method,
        sort_text: method.name,
        text_edit: LSP::TextEdit.new(
          range: @context.completion_range(@line_number),
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

    private def variable_completion_item(name : String, *, kind = LSP::CompletionItemKind::Variable, detail : String? = nil, insert_text : String = name) : LSP::CompletionItem
      LSP::CompletionItem.new(
        label: detail || name,
        insert_text: insert_text,
        filter_text: name,
        detail: detail,
        kind: kind,
        sort_text: name,
        text_edit: LSP::TextEdit.new(
          range: @context.completion_range(@line_number),
          new_text: insert_text,
        ),
      )
    end

    private def type_completion_item(type : TypeInfo) : LSP::CompletionItem
      LSP::CompletionItem.new(
        label: type.name,
        insert_text: type.name,
        filter_text: type.name,
        detail: type.kind.to_s,
        kind: type_completion_kind(type.kind),
        sort_text: type.name,
        text_edit: LSP::TextEdit.new(
          range: @context.completion_range(@line_number),
          new_text: type.name,
        ),
        documentation: type.doc.try { |doc|
          LSP::MarkupContent.new(
            kind: LSP::MarkupKind::MarkDown,
            value: doc,
          )
        },
      )
    end

    private def self_completion_detail(inference : Inference?) : String?
      return unless inference

      type_names, class_method = inference.self_types
      return if type_names.empty?

      class_method ? "self : #{type_names.uniq.join(" | ")}.class" : "self : #{type_names.uniq.join(" | ")}"
    end

    private def current_fragment : String
      line = @source.lines(chomp: false)[@line_number]? || ""
      line[@context.replace_start...@context.replace_end]? || ""
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

    private def type_completion_kind(kind : TypeKind)
      case kind
      when .class?
        LSP::CompletionItemKind::Class
      when .module?
        LSP::CompletionItemKind::Module
      when .struct?
        LSP::CompletionItemKind::Struct
      when .enum?
        LSP::CompletionItemKind::Enum
      else
        LSP::CompletionItemKind::Class
      end
    end
  end
end
