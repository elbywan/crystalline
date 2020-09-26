struct Enum
  # An JSON fiendly string enum.
  macro string(name, *, downcase = true, mappings = nil, &block)
    enum {{ name.id }}
      {{ block.body }}

      def self.parse(string : String) : self
        {% if mappings %}
        	{% for key, value in mappings %}
	          return self.new({{ key }}) if string == {{ value }}
          {% end %}
        {% end %}
        super
      end

      def to_json(builder : JSON::Builder) : IO
        builder.string self.to_s{% if downcase %}.downcase{% end %}
      end

	    def to_s(io : IO) : Nil
      	io << self.to_s
    	end

      def to_s : String
        {% if mappings %}
          {% for key, value in mappings %}
      			return {{ value }} if self == {{ key }}
          {% end %}
        {% end %}
      	super{% if downcase %}.downcase{% end %}
      end
    end
  end
end
