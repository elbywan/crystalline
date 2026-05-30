require "spec"
require "lsp/server"
require "../src/crystalline/completion_context"

describe Crystalline::CompletionContext do
  it "returns nil inside comments" do
    context = Crystalline::CompletionContext.detect("foo # bar.", 10, ".")
    context.should be_nil
  end

  it "detects dot completion from an identifier fragment" do
    context = Crystalline::CompletionContext.detect("foo.ba", 6, nil)
    context.should_not be_nil
    context = context.not_nil!

    context.trigger_character.should eq(".")
    context.analysis_column.should eq(3)
    context.replace_start.should eq(4)
    context.replace_end.should eq(6)
    context.rewritten_line.should eq("foo")
  end

  it "detects namespace completion from a path fragment" do
    context = Crystalline::CompletionContext.detect("Foo::Ba", 7, nil)
    context.should_not be_nil
    context = context.not_nil!

    context.trigger_character.should eq(":")
    context.analysis_column.should eq(3)
    context.replace_start.should eq(5)
    context.replace_end.should eq(7)
    context.rewritten_line.should eq("Foo")
  end

  it "detects ivar completion and excludes the sigil from replacement" do
    context = Crystalline::CompletionContext.detect("@iv", 3, nil)
    context.should_not be_nil
    context = context.not_nil!

    context.trigger_character.should eq("@")
    context.analysis_column.should eq(0)
    context.replace_start.should eq(1)
    context.replace_end.should eq(3)
    context.rewritten_line.should eq("")
  end

  it "handles explicit dot triggers" do
    context = Crystalline::CompletionContext.detect("foo.", 4, ".")
    context.should_not be_nil
    context = context.not_nil!

    context.trigger_character.should eq(".")
    context.analysis_column.should eq(3)
    context.replace_start.should eq(4)
    context.replace_end.should eq(4)
    context.rewritten_line.should eq("foo")
  end
end
