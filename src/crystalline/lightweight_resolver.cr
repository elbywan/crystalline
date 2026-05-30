require "./lightweight_inference"
require "./lightweight_query"

module Crystalline::Lightweight
  module Resolver
    extend self

    def receiver_types(source : String, line_number : Int32, analysis_column : Int32, receiver : String, query : Query) : {Array(String), Bool}
      if type_name?(receiver)
        return {[receiver], true} if query.find_type(receiver)
        return {[] of String, true}
      end

      return {[] of String, false} unless local_name?(receiver)

      inference = Inference.for(
        source,
        line_number + 1,
        analysis_column + 1,
        query,
      )

      return {[] of String, false} unless inference

      {
        inference.types_for(receiver).select { |type_name| query.find_type(type_name) != nil },
        false,
      }
    end

    def receiver_from_prefix(prefix : String) : String
      start = prefix.size

      while start > 0 && receiver_char?(prefix[start - 1])
        start -= 1
      end

      prefix[start..]? || ""
    end

    def receiver_char?(char : Char)
      char.ascii_alphanumeric? || char.in?('_', '?', '!', '@', ':')
    end

    def local_name?(name : String)
      !!(name =~ /\A[a-z_][a-zA-Z0-9_?!]*\z/)
    end

    def type_name?(name : String)
      !!(name =~ /\A[A-Z][a-zA-Z0-9_]*(?:::[A-Z][a-zA-Z0-9_]*)*\z/)
    end
  end
end
