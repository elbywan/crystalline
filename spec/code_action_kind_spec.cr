require "spec"
require "lsp/server"

describe LSP::CodeActionKind do
  it "parses the kinds announced by the shard" do
    LSP::CodeActionKind.parse("quickfix").should eq(LSP::CodeActionKind::QuickFix)
    LSP::CodeActionKind.parse("refactor.extract").should eq(LSP::CodeActionKind::RefactorExtract)
  end

  it "parses the sub-kinds the shard maps" do
    LSP::CodeActionKind.parse("source.fixAll").should eq(LSP::CodeActionKind::SourceFixAll)
  end

  it "ignores custom and unmapped sub-kinds" do
    LSP::CodeActionKind.parse("custom.kind").should eq(LSP::CodeActionKind::Empty)
    LSP::CodeActionKind.parse("refactor.extract.function").should eq(LSP::CodeActionKind::Empty)
  end

  it "deserializes client capabilities announcing custom code action kinds" do
    params = LSP::InitializeParams.from_json(%({
      "capabilities": {
        "textDocument": {
          "codeAction": {
            "codeActionLiteralSupport": {
              "codeActionKind": { "valueSet": ["source.fixAll", "quickfix"] }
            }
          }
        }
      }
    }))

    value_set = params.capabilities.text_document.not_nil!
      .code_action.not_nil!
      .code_action_literal_support.not_nil!
      .code_action_kind.not_nil!
      .value_set.not_nil!

    value_set.should eq([LSP::CodeActionKind::SourceFixAll, LSP::CodeActionKind::QuickFix])
  end
end
