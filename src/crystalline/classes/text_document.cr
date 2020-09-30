require "priority-queue"
require "uri"

class Crystalline::TextDocument
  getter uri : URI
  @inner_contents : Array(String) = [] of String
  getter! version : Int32
  @pending_changes : Priority::Queue({String, LSP::Range}) = Priority::Queue({String, LSP::Range}).new

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

  alias ContentChange = { contents: String, range: LSP::Range? }
  def update_contents(content_changes = Array(ContentChange), version : Number? = nil)
    content_changes.each { |change|
      update_contents(*change, version: version)
    }

    # Check for pending changes
    loop do
      break unless @pending_changes.first?.try(&.priority.== self.version + 1)
      item = @pending_changes.shift
      partial_update(*item.value, version: item.priority)
    end
  end

  private def update_contents(contents : String, range : LSP::Range? = nil, version : Number? = nil)
    if range
      # Incremental update
      if version && check_version(version)
        # Version is up-to-date
        partial_update(contents, range, version)
      elsif version
        # Some updates are missing
        @pending_changes.push version, {contents, range}
      else
        # No version field.
        partial_update(contents, range, version)
      end
    else
      # Full update
      full_update(contents)
    end
  end

  private def check_version(version : Number)
    @version ||= version
    @version == version - 1 || @version == version
  end

  private def partial_update(contents : String, range : LSP::Range, version : Number? = nil)
    prefix = @inner_contents[range.start.line]?.try &.[...range.start.character].chomp || ""
    suffix = @inner_contents[range.end.line]?.try &.[range.end.character..]? || @inner_contents[range.end.line]? || ""
    replacement_lines = String.build { |str|
      str << prefix << contents << suffix
    }.lines(chomp: false)
    @inner_contents = (@inner_contents[...range.start.line]? || [] of String) + replacement_lines + (@inner_contents[range.end.line + 1...]? || [] of String)
    @version = version if version
  end

  private def full_update(contents : String)
    self.contents = contents
  end
end
