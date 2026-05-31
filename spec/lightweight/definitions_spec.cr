require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/lightweight/definitions"

private def build_definition_query(source : String)
  index = Crystalline::Lightweight::Index.from_source(source)
  raise "expected syntax index" unless index
  Crystalline::Lightweight::Query.new(index)
end

describe Crystalline::Lightweight::Definitions do
  it "finds type definitions in standalone syntax-only files" do
    source = <<-CRYSTAL
      class Clazz
      end

      puts Clazz
    CRYSTAL

    file_uri = URI.parse("file:///tmp/standalone.cr")
    query = build_definition_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |line| line.includes?("puts Clazz") }
    character = lines[line_number].rindex("Clazz").not_nil! + 2

    locations = Crystalline::Lightweight::Definitions.definitions(source, file_uri, line_number, character, query)
    locations.should_not be_nil
    locations.not_nil!.first.range.start.line.should eq(0)
  end

  it "finds method definitions for resolved receivers" do
    source = <<-CRYSTAL
      class Clazz
        def method1(num : Int32)
          2
        end
      end

      puts Clazz.new.method1(num: 42)
    CRYSTAL

    file_uri = URI.parse("file:///tmp/standalone.cr")
    query = build_definition_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |line| line.includes?("Clazz.new.method1") }
    character = lines[line_number].rindex("method1").not_nil! + 2

    locations = Crystalline::Lightweight::Definitions.definitions(source, file_uri, line_number, character, query)
    locations.should_not be_nil
    locations.not_nil!.first.range.start.line.should eq(1)
  end

  it "finds top-level method definitions" do
    source = <<-CRYSTAL
      def helper
        1
      end

      helper
    CRYSTAL

    file_uri = URI.parse("file:///tmp/standalone.cr")
    query = build_definition_query(source)
    lines = source.lines(chomp: false)
    line_number = lines.index! { |line| line.strip == "helper" }
    character = lines[line_number].index("helper").not_nil! + 2

    locations = Crystalline::Lightweight::Definitions.definitions(source, file_uri, line_number, character, query)
    locations.should_not be_nil
    locations.not_nil!.first.range.start.line.should eq(0)
  end
end
