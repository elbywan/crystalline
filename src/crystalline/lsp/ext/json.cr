module JSON::Serializable
  # This extension adds a default type to deserialize the json into, in case the discriminator value is not covered by the mappings.
  macro json_discriminator(field, mapping, *, default = nil)
    {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
      {% mapping.raise "mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
    {% end %}

    def self.new(pull : ::JSON::PullParser)
      location = pull.location

      discriminator_value = nil

      # Try to find the discriminator while also getting the raw
      # string value of the parsed JSON, so then we can pass it
      # to the final type.
      json = String.build do |io|
        JSON.build(io) do |builder|
          builder.start_object
          pull.read_object do |key|
            if key == {{field.id.stringify}}
              discriminator_value = pull.read_string
              builder.field(key, discriminator_value)
            else
              builder.field(key) { pull.read_raw(builder) }
            end
          end
          builder.end_object
        end
      end

      unless discriminator_value
        {% if default %}
          return {{ default.id }}.from_json(json)
        {% else %}
          raise ::JSON::MappingError.new("Missing JSON discriminator field '{{field.id}}'", to_s, nil, *location, nil)
        {% end %}
      end

      case discriminator_value
      {% for key, value in mapping %}
        when {{key.id.stringify}}
          {{value.id}}.from_json(json)
      {% end %}
      else
        {% if default %}
          return {{ default.id }}.from_json(json)
        {% else %}
          raise ::JSON::MappingError.new("Unknown '{{field.id}}' discriminator value: #{discriminator_value.inspect}", to_s, nil, *location, nil)
        {% end %}
      end
    end
  end
end
