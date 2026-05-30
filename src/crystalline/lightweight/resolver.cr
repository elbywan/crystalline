require "./inference"
require "./query"

module Crystalline::Lightweight
  module Resolver
    extend self

    def receiver_types(source : String, line_number : Int32, analysis_column : Int32, receiver : String, query : Query) : {Array(String), Bool}
      segments = receiver.split('.')
      return {[] of String, false} if segments.empty?

      type_names, class_method = root_receiver_types(source, line_number, analysis_column, segments.shift, query)
      return {[] of String, class_method} if type_names.empty?

      segments.each do |segment|
        type_names, class_method = chained_call_types(type_names, class_method, segment, query)
        return {[] of String, class_method} if type_names.empty?
      end

      {type_names, class_method}
    end

    def receiver_from_prefix(prefix : String) : String
      start = prefix.size

      while start > 0 && receiver_expression_char?(prefix[start - 1])
        start -= 1
      end

      prefix[start..]? || ""
    end

    def receiver_expression_char?(char : Char)
      token_char?(char) || char == '.'
    end

    def token_char?(char : Char)
      char.ascii_alphanumeric? || char.in?('_', '?', '!', '@', ':')
    end

    def instance_var_name?(name : String)
      !!(name =~ /\A@[a-zA-Z_][a-zA-Z0-9_?!]*\z/)
    end

    def class_var_name?(name : String)
      !!(name =~ /\A@@[a-zA-Z_][a-zA-Z0-9_?!]*\z/)
    end

    def local_name?(name : String)
      !!(name =~ /\A[a-z_][a-zA-Z0-9_?!]*\z/)
    end

    def type_name?(name : String)
      !!(name =~ /\A[A-Z][a-zA-Z0-9_]*(?:::[A-Z][a-zA-Z0-9_]*)*\z/)
    end

    private def root_receiver_types(source : String, line_number : Int32, analysis_column : Int32, receiver : String, query : Query) : {Array(String), Bool}
      if type_name?(receiver)
        return {[receiver], true} if query.find_type(receiver)
        return {[] of String, true}
      end

      inference = Inference.for(
        source,
        line_number + 1,
        analysis_column + 1,
        query,
      )

      if receiver == "self"
        return inference.try(&.self_types) || {[] of String, false}
      end

      if instance_var_name?(receiver)
        return {
          (inference ? inference.types_for_instance_var(receiver) : [] of String).select { |type_name| query.find_type(type_name) != nil },
          false,
        }
      end

      if class_var_name?(receiver)
        return {
          (inference ? inference.types_for_class_var(receiver) : [] of String).select { |type_name| query.find_type(type_name) != nil },
          true,
        }
      end

      return {[] of String, false} unless local_name?(receiver)

      if inference
        local_types = inference.types_for(receiver).select { |type_name| query.find_type(type_name) != nil }
        return {local_types, false} unless local_types.empty?
      end

      {
        query.top_level_methods.select { |method| method.name == receiver && method.args.empty? }.compact_map { |method|
          return_type = method.return_type
          return_type if return_type && query.find_type(return_type)
        }.uniq,
        false,
      }
    end

    private def chained_call_types(type_names : Array(String), class_method : Bool, method_name : String, query : Query) : {Array(String), Bool}
      if class_method
        return {type_names.select { |type_name| query.find_type(type_name) != nil }.uniq, false} if method_name == "new"
        return {type_names.select { |type_name| query.find_type(type_name) != nil }.uniq, true} if method_name == "class"
      elsif method_name == "class"
        return {type_names.select { |type_name| query.find_type(type_name) != nil }.uniq, true}
      end

      return_types = type_names.flat_map do |type_name|
        query.methods_for(type_name, class_method: class_method).select { |method|
          method.name == method_name && method.args.empty?
        }.compact_map do |method|
          return_type = method.return_type
          return_type if return_type && query.find_type(return_type)
        end
      end

      {return_types.uniq, false}
    end
  end
end
