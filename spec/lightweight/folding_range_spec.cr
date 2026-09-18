require "spec"
require "../../src/crystalline/lightweight/folding_range"

private def fold_tuples(source : String) : Array(Tuple(Int32, Int32, LSP::FoldingRangeKind?))
  Crystalline::Lightweight::FoldingRange.ranges(source).not_nil!.map do |range|
    {range.start_line, range.end_line, range.kind}
  end
end

describe Crystalline::Lightweight::FoldingRange do
  it "folds classes and modules onto their closing end" do
    source = <<-CRYSTAL
      class Greeter
        def greet
          "hi"
        end
      end

      module Helpers
        def self.help
        end
      end
      CRYSTAL

    fold_tuples(source).should eq([
      {0, 4, nil},
      {1, 3, nil},
      {6, 9, nil},
      {7, 8, nil},
    ])
  end

  it "emits line based ranges without character offsets" do
    source = <<-CRYSTAL
      class Greeter
        def greet
          "hi"
        end
      end
      CRYSTAL

    Crystalline::Lightweight::FoldingRange.ranges(source).not_nil!.each do |range|
      range.start_character.should be_nil
      range.end_character.should be_nil
    end
  end

  it "folds defs and do-end blocks" do
    source = <<-CRYSTAL
      def demo
        items = [1, 2]
        items.each do |item|
          item
        end
      end
      CRYSTAL

    fold_tuples(source).should eq([
      {0, 5, nil},
      {2, 4, nil},
    ])
  end

  it "folds if expressions" do
    source = <<-CRYSTAL
      if condition
        run
      else
        skip
      end
      CRYSTAL

    fold_tuples(source).should eq([{0, 4, nil}])
  end

  it "folds case expressions" do
    source = <<-CRYSTAL
      case value
      when 1
        :one
      else
        :other
      end
      CRYSTAL

    fold_tuples(source).should eq([{0, 5, nil}])
  end

  it "folds begin blocks with and without a handler" do
    source = <<-CRYSTAL
      begin
        work
      rescue error
        handle(error)
      end
      CRYSTAL

    fold_tuples(source).should eq([{0, 4, nil}])

    plain = <<-CRYSTAL
      begin
        work
      end
      CRYSTAL

    fold_tuples(plain).should eq([{0, 2, nil}])
  end

  it "folds the remaining block kinds" do
    source = <<-CRYSTAL
      while running
        tick
      end

      until done
        work
      end

      select
      when channel.receive
        handle
      end

      macro define_it
        def generated
        end
      end

      enum Color
        Red
        Green
      end

      lib LibC
        fun puts(str : UInt8*) : Int32
      end

      annotation Marker
      end
      CRYSTAL

    fold_tuples(source).should eq([
      {0, 2, nil},
      {4, 6, nil},
      {8, 11, nil},
      {13, 16, nil},
      {18, 21, nil},
      {23, 25, nil},
      {27, 28, nil},
    ])
  end

  it "does not fold comment or require lines inside a heredoc" do
    source = <<-CR
    text = <<-TEXT
      # not a comment
      # still not
      require "not/an/import"
      require "neither"
      TEXT
    CR

    fold_tuples(source).should eq([{0, 5, nil}])
  end

  it "folds multiline literals" do
    source = <<-'CRYSTAL'
      doc = <<-TEXT
        line one
        line two
        TEXT
      CRYSTAL

    fold_tuples(source).should eq([{0, 3, nil}])
  end

  it "folds two or more consecutive comment lines into a single comment range" do
    source = <<-CRYSTAL
      # first
      # second

      def demo
        run
      end
      CRYSTAL

    fold_tuples(source).should eq([
      {0, 1, LSP::FoldingRangeKind::Comment},
      {3, 5, nil},
    ])
  end

  it "does not fold a lone comment" do
    source = <<-CRYSTAL
      # lone

      # other
      def demo
        run
      end
      CRYSTAL

    fold_tuples(source).should eq([{3, 5, nil}])
  end

  it "folds two or more consecutive require lines into a single imports range" do
    source = <<-CRYSTAL
      require "json"
      require "uri"

      def demo
        run
      end
      CRYSTAL

    fold_tuples(source).should eq([
      {0, 1, LSP::FoldingRangeKind::Imports},
      {3, 5, nil},
    ])
  end

  it "emits a single range when a postfix condition shares a block span" do
    source = <<-CRYSTAL
      def demo(args)
        return unless args.all? do |arg|
          arg
        end
      end
      CRYSTAL

    fold_tuples(source).should eq([
      {0, 4, nil},
      {1, 3, nil},
    ])
  end

  it "does not fold a single line def" do
    Crystalline::Lightweight::FoldingRange.ranges("def demo; run; end\n").should be_nil
  end

  it "returns nil when nothing folds" do
    Crystalline::Lightweight::FoldingRange.ranges("").should be_nil
  end

  it "keeps the line ranges of a buffer that does not parse" do
    source = <<-CRYSTAL
      # still foldable
      # second comment

      class Broken
        def oops(
      CRYSTAL

    fold_tuples(source).should eq([{0, 1, LSP::FoldingRangeKind::Comment}])
  end

  it "returns nil for a flat buffer that does not parse" do
    Crystalline::Lightweight::FoldingRange.ranges("def broken(\n").should be_nil
  end
end
