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
      def initialize(args : NamedTuple)
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

  module Async
    def self.spawn_on_different_thread(thread : Thread, &block : ->) : Nil
      block
      {% if flag?(:preview_mt) %}
        spawn same_thread: false do
          if Thread.current == thread
            spawn_on_different_thread(thread, &block)
          else
            block.call
          end
        end
      {% else %}
        spawn(&block)
      {% end %}
    end
  end
end
