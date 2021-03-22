# Crystal > 0.36.1 serializes enums from/to strings now.
# This is a breaking change, and it conflicts with how the LSP protocol works.
# Using the officially suggested converters for every possible fields (and making custom converters for array of enums)
# suck, hence the following monkey patches to revert to the original behaviour.

struct Enum
  def to_json(json : JSON::Builder)
    json.number(value)
  end
end

def Enum.new(pull : JSON::PullParser)
  {% if @type.annotation(Flags) %}
    if pull.kind.begin_array?
      value = 0
      pull.read_array do
        value += new(pull).value
      end
      return from_value(value)
    end
  {% end %}

  case pull.kind
  when .int?
    from_value(pull.read_int)
  when .string?
    parse(pull.read_string)
  else
    {% if @type.annotation(Flags) %}
      raise "Expecting int, string or array in JSON for #{self.class}, not #{pull.kind}"
    {% else %}
      raise "Expecting int or string in JSON for #{self.class}, not #{pull.kind}"
    {% end %}
  end
end
