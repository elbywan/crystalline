require "spec"
require "../../src/crystalline/requires"
require "../../src/crystalline/main"
require "../../src/crystalline/lightweight/signature_help"

# The cursor marker, removed from the source before the request.
SIGNATURE_HELP_CURSOR = "‸"

private def build_signature_query(source : String)
  index = Crystalline::Lightweight::Index.from_source(source)
  raise "expected syntax index" unless index
  Crystalline::Lightweight::Query.new(index)
end

private def locate_signature_cursor(source : String) : {String, Int32, Int32}
  marker = source.index(SIGNATURE_HELP_CURSOR).not_nil!
  stripped = source.sub(SIGNATURE_HELP_CURSOR, "")
  prefix = stripped[0, marker]
  if newline = prefix.rindex('\n')
    line = prefix[newline + 1..]
    {stripped, prefix.count('\n'), Crystalline::PositionUtils.char_to_utf16_index(line, line.size)}
  else
    {stripped, 0, Crystalline::PositionUtils.char_to_utf16_index(prefix, prefix.size)}
  end
end

private def signature_help(source : String, query_source : String? = nil) : LSP::SignatureHelp?
  stripped, line_number, column_number = locate_signature_cursor(source)
  query = build_signature_query(query_source || stripped)
  Crystalline::Lightweight::SignatureHelp.help(stripped, line_number, column_number, query)
end

private def signature_labels(help : LSP::SignatureHelp) : Array(String)
  help.signatures.map(&.label)
end

describe Crystalline::Lightweight::SignatureHelp do
  it "reports the active parameter of a plain call" do
    source = <<-CRYSTAL
      def foo(a : Int32, b : Int32, c : Int32)
      end

      foo(1, ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
    help.not_nil!.active_signature.should eq(0)
    signatures = help.not_nil!.signatures
    signature_labels(help.not_nil!).should eq(["foo(a : Int32, b : Int32, c : Int32)"])
    signatures.first.parameters.not_nil![1].label.should eq({15, 24})
  end

  it "returns nil without a query" do
    source = "def foo(a, b)\nend\n\nfoo(1, )\n"
    Crystalline::Lightweight::SignatureHelp.help(source, 3, 6, nil).should be_nil
  end

  it "counts only top-level commas of nested calls" do
    source = <<-CRYSTAL
      def foo(a : Int32, b : Int32)
      end

      def bar(a : Int32, b : Int32)
      end

      foo(bar(1, 2), ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
    signature_labels(help.not_nil!).should eq(["foo(a : Int32, b : Int32)"])
  end

  it "resolves receiver calls" do
    source = <<-CRYSTAL
      class Greeter
        def greet(name : String, punctuation : String)
        end
      end

      Greeter.new.greet("hi", ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
    signature_labels(help.not_nil!).should eq(["greet(name : String, punctuation : String)"])
  end

  it "resolves self-calls on the enclosing type" do
    source = <<-CRYSTAL
      class Greeter
        def greet(name : String, punctuation : String)
        end

        def demo
          greet("hi", ‸)
        end
      end
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
    signature_labels(help.not_nil!).should eq(["greet(name : String, punctuation : String)"])
  end

  it "returns nil for an unresolved receiver chain" do
    source = <<-CRYSTAL
      class Demo
        def foo(a : Int32)
        end

        def demo
          {1 => 2}.foo(1, ‸)
        end
      end
      CRYSTAL

    signature_help(source).should be_nil
  end

  it "ignores commas inside string literals" do
    source = <<-CRYSTAL
      def log(a : String, b : String)
      end

      log("a,b", ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
  end

  it "does not let parentheses and commas inside literals unbalance the scan" do
    source = <<-CRYSTAL
      def log(a : String, b : String)
      end

      log("(:, ))", ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
  end

  it "ignores literals inside interpolations" do
    source = <<-CRYSTAL
      def log(a : String, b : String)
      end

      name = "x"
      log("\#{name},y", ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
  end

  it "ignores heredoc bodies" do
    source = <<-CRYSTAL
      def log(a : String, b : String)
      end

      text = <<-TEXT
      (,))
      TEXT

      log(text, ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
  end

  it "converts the cursor column from UTF-16" do
    source = <<-CRYSTAL
      def log(a : String, b : String)
      end

      log("🎉,b", ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
  end

  it "ignores commas inside regex literals" do
    source = <<-CRYSTAL
      def log(a : String, b : String, c : String)
      end

      log("x", /a,b/, ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(2)
  end

  it "ignores commas inside percent literals" do
    source = <<-CRYSTAL
      def log(a : String, b : String, c : String)
      end

      log("y", %q(a,b), ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(2)
  end

  it "ignores commas inside percent arrays" do
    source = <<-CRYSTAL
      def log(a : String, b : Array(String), c : String)
      end

      log("y", %w(a,b), ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(2)
  end

  it "renders splat, double-splat and block arguments" do
    source = <<-CRYSTAL
      def each_entry(name : String, *values, **options, &block)
      end

      each_entry("x", ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    signatures = help.not_nil!.signatures
    signatures.first.label.should eq("each_entry(name : String, *values, **options, &block)")
    signatures.first.parameters.not_nil!.size.should eq(4)
    help.not_nil!.active_parameter.should eq(1)
  end

  it "keeps the active parameter in range when the call has more commas than parameters" do
    source = <<-CRYSTAL
      def one(a : Int32)
      end

      one(1, 2, 3, ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(0)
  end

  it "reports no active parameter for a signature without parameters" do
    source = <<-CRYSTAL
      def none
      end

      none(‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should be_nil
    help.not_nil!.signatures.first.label.should eq("none()")
  end

  it "selects the first overload that can hold the argument count" do
    source = <<-CRYSTAL
      def pick(a : Int32)
      end

      def pick(a : Int32, b : Int32)
      end

      pick(1, ‸)
      CRYSTAL

    help = signature_help(source)
    help.should_not be_nil
    help.not_nil!.active_signature.should eq(1)
    help.not_nil!.active_parameter.should eq(1)
  end

  it "returns nil inside comments and literals" do
    string_source = <<-CRYSTAL
      def log(a : String, b : String)
      end

      log("a,‸b", "")
      CRYSTAL
    signature_help(string_source).should be_nil

    comment_source = <<-CRYSTAL
      def log(a : String, b : String)
      end

      log("a", "b") # log(‸)
      CRYSTAL
    signature_help(comment_source).should be_nil
  end

  it "resolves a plain call in an unparseable buffer" do
    query_source = "def foo(a : Int32, b : Int32)\nend\n"
    broken = "def foo(a : Int32, b : Int32)\nend\nfoo(1, ‸"
    Crystalline::Lightweight::Index.from_source(broken.sub(SIGNATURE_HELP_CURSOR, "")).should be_nil

    help = signature_help(broken, query_source)
    help.should_not be_nil
    help.not_nil!.active_parameter.should eq(1)
    signature_labels(help.not_nil!).should eq(["foo(a : Int32, b : Int32)"])
  end
end
