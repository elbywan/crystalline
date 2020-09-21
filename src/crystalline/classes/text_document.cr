require "uri"

class Crystalline::TextDocument
  getter uri : URI
  @inner_contents : Array(String) = [] of String

  def initialize(uri : String, contents : String)
    @uri = URI.parse(uri)
    self.contents = contents
  end

  def contents=(contents : String)
    @inner_contents = contents.lines(chomp: false)
  end

  def contents : String
    @inner_contents.join
  end

  def lines_nb : Int32
    @inner_contents.size
  end

  def update_contents(contents : String, range : LSP::Range? = nil)
    if range
      prefix = @inner_contents[range.start.line]?.try &.[...range.start.character].chomp || ""
      suffix = @inner_contents[range.end.line]?.try &.[range.end.character..]? || @inner_contents[range.end.line]? || ""
      replacement_lines = (prefix + contents + suffix).lines(chomp: false)
      @inner_contents = (@inner_contents[...range.start.line]? || [] of String) + replacement_lines + (@inner_contents[range.end.line + 1...]? || [] of String)
    else
      self.contents = contents
    end
  end
end
