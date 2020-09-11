require "uri"

class Crystalline::TextDocument
  getter uri : URI
  getter contents : String
  getter lines_nb : Int32

  def contents=(contents : String)
    @lines_nb = contents.lines.size
    @contents = contents
  end

  def initialize(uri : String, @contents)
    @lines_nb = @contents.lines.size
    @uri = URI.parse(uri)
  end
end
