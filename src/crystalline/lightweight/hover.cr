require "lsp/server"
require "./query"
require "./resolver"

module Crystalline::Lightweight
  class Hover
    def self.hover(source : String, line_number : Int32, column_number : Int32, query : Query) : LSP::Hover?
      new(source, line_number, column_number, query).hover
    end

    def self.diagnose(source : String, line_number : Int32, column_number : Int32, query : Query) : String
      new(source, line_number, column_number, query).diagnose
    end

    def initialize(@source : String, @line_number : Int32, @column_number : Int32, @query : Query)
    end

    def hover : LSP::Hover?
      line = @source.lines(chomp: false)[@line_number]?
      return unless line

      hover_or_reason(line)[0]
    end

    def diagnose : String
      line = @source.lines(chomp: false)[@line_number]?
      return "no line at cursor" unless line

      hover_or_reason(line)[1]
    end

    private def hover_or_reason(line : String) : {LSP::Hover?, String}
      span = token_span(line)
      return {nil, "no token at cursor"} unless span

      start_index, end_index = span
      token = line[start_index, end_index - start_index]?
      return {nil, "empty token at cursor"} unless token && !token.empty?

      if start_index > 0 && line[start_index - 1] == '.'
        receiver = Resolver.receiver_from_prefix(line[0, start_index - 1])
        return {nil, "empty method receiver"} if receiver.empty?

        hover = hover_for_method(receiver, token, start_index - 1)
        return {hover, hover ? "resolved" : "no lightweight method hover for receiver '#{receiver}' and method '#{token}'"}
      end

      if token == "self"
        hover = hover_for_self
        return {hover, hover ? "resolved" : "could not infer self type"}
      end

      if Resolver.type_name?(token)
        hover = hover_for_type(token)
        return {hover, hover ? "resolved" : "unknown lightweight type '#{token}'"}
      end

      if Resolver.instance_var_name?(token)
        hover = hover_for_instance_var(token)
        return {hover, hover ? "resolved" : "could not infer instance var '#{token}'"}
      end

      if Resolver.class_var_name?(token)
        hover = hover_for_class_var(token)
        return {hover, hover ? "resolved" : "could not infer class var '#{token}'"}
      end

      if Resolver.local_name?(token)
        hover = hover_for_local(token) || hover_for_top_level_method(token)
        return {hover, hover ? "resolved" : "could not infer local or top-level method '#{token}'"}
      end

      {nil, "unsupported hover token '#{token}'"}
    end

    private def hover_for_method(receiver : String, method_name : String, analysis_column : Int32) : LSP::Hover?
      type_names, class_method = Resolver.receiver_types(@source, @line_number, analysis_column, receiver, @query)
      return if type_names.empty?

      methods = type_names.flat_map do |type_name|
        @query.methods_for(type_name, class_method: class_method).select { |method| method.name == method_name }
      end
      return if methods.empty?

      build_hover(
        methods.map { |method| format_method(method, include_owner: true) },
        methods.compact_map(&.doc).first?,
      )
    end

    private def hover_for_type(type_name : String) : LSP::Hover?
      type = @query.find_type(type_name)
      return unless type

      build_hover([type.name], type.doc)
    end

    private def hover_for_self : LSP::Hover?
      inference = Inference.for(@source, @line_number + 1, @column_number + 1, @query)
      return unless inference

      type_names, class_method = inference.self_types
      return if type_names.empty?

      label = class_method ? "self : #{type_names.uniq.join(" | ")}.class" : "self : #{type_names.uniq.join(" | ")}"
      doc = type_names.size == 1 ? @query.find_type(type_names.first).try(&.doc) : nil
      build_hover([label], doc)
    end

    private def hover_for_local(name : String) : LSP::Hover?
      inference = Inference.for(@source, @line_number + 1, @column_number + 1, @query)
      return unless inference

      type_names = inference.types_for(name)
      return if type_names.empty?

      doc = type_names.size == 1 ? @query.find_type(type_names.first).try(&.doc) : nil
      build_hover(["#{name} : #{type_names.uniq.join(" | ")}"], doc)
    end

    private def hover_for_instance_var(name : String) : LSP::Hover?
      inference = Inference.for(@source, @line_number + 1, @column_number + 1, @query)
      return unless inference

      type_names = inference.types_for_instance_var(name)
      return if type_names.empty?

      doc = type_names.size == 1 ? @query.find_type(type_names.first).try(&.doc) : nil
      build_hover(["#{name} : #{type_names.uniq.join(" | ")}"], doc)
    end

    private def hover_for_class_var(name : String) : LSP::Hover?
      inference = Inference.for(@source, @line_number + 1, @column_number + 1, @query)
      return unless inference

      type_names = inference.types_for_class_var(name)
      return if type_names.empty?

      doc = type_names.size == 1 ? @query.find_type(type_names.first).try(&.doc) : nil
      build_hover(["#{name} : #{type_names.uniq.join(" | ")}"], doc)
    end

    private def hover_for_top_level_method(method_name : String) : LSP::Hover?
      methods = @query.top_level_methods.select { |method| method.name == method_name }
      return if methods.empty?

      build_hover(
        methods.map { |method| format_method(method, include_owner: true) },
        methods.compact_map(&.doc).first?,
      )
    end

    private def build_hover(signatures : Array(String), doc : String?) : LSP::Hover
      contents = [] of String
      contents << code_markdown(signatures.uniq.join("\n"), language: "crystal")

      if doc
        contents << "----------"
        contents << doc
      end

      LSP::Hover.new(
        contents: LSP::MarkupContent.new(
          kind: LSP::MarkupKind::MarkDown,
          value: contents.join("\n"),
        ),
      )
    end

    private def code_markdown(str : String, *, language = "") : String
      <<-MARKDOWN
      ```#{language}
      #{str}
      ```
      MARKDOWN
    end

    private def format_method(method : MethodInfo, *, include_owner = false) : String
      args = method.args.map do |arg|
        if restriction = arg.restriction
          "#{arg.name} : #{restriction}"
        else
          arg.name
        end
      end.join(", ")

      String.build do |str|
        if include_owner
          str << method.owner
          str << (method.class_method ? "." : "#")
        end

        str << method.name
        str << "(#{args})"
        str << " : #{method.return_type}" if method.return_type
      end
    end

    private def token_span(line : String) : {Int32, Int32}?
      index = normalized_column(line)
      return unless index
      return unless token_char?(line[index])

      start_index = index
      while start_index > 0 && token_char?(line[start_index - 1])
        start_index -= 1
      end

      end_index = index + 1
      while (char = line[end_index]?) && token_char?(char)
        end_index += 1
      end

      {start_index, end_index}
    end

    private def normalized_column(line : String) : Int32?
      return if line.empty?

      index = @column_number
      index = line.size - 1 if index >= line.size
      return if index < 0

      return index if token_char?(line[index])
      return index - 1 if index > 0 && token_char?(line[index - 1])

      nil
    end

    private def token_char?(char : Char)
      Resolver.token_char?(char)
    end
  end
end
