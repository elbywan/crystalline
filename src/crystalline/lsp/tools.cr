module LSP
  class StringEnumConverter(T)
    def from_json(parser : JSON::PullParser)
      T.new(parser)
    end

    def to_json(value : T, builder : JSON::Builder)
      builder.string(value.to_s.camelcase(lower: true))
    end
  end

  module Initializer
    macro included
      {% verbatim do %}
      def self.new(**args)
        instance = self.allocate
        instance.initialize(args)
        instance
      end

      private def initialize(args : NamedTuple)
        {% for ivar in @type.instance_vars %}
          {% default_value = ivar.default_value %}
          {% if ivar.type.nilable? %}
            @{{ivar.id}} = args["{{ivar.id}}"]? {% if ivar.has_default_value? %}|| {{ default_value }}{% end %}
          {% else %}
            {% if ivar.has_default_value? %}
              @{{ivar.id}} = args["{{ivar.id}}"]? || {{ default_value }}
            {% else %}
              @{{ivar.id}} = args["{{ivar.id}}"]
            {% end %}
          {% end %}
        {% end %}
      end
      {% end %}
    end
  end
end
