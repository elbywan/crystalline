module Crystalline::Utils
  def self.map_completion_kind(kind, *, default = LSP::CompletionItemKind::Variable)
    case kind
    when Crystal::FileModule
      LSP::CompletionItemKind::File
    when Crystal::Const
      LSP::CompletionItemKind::Constant
    when Crystal::ClassType
      LSP::CompletionItemKind::Class
    when Crystal::EnumType
      LSP::CompletionItemKind::Enum
    when Crystal::LibType
      LSP::CompletionItemKind::Interface
    when Crystal::ModuleType
      LSP::CompletionItemKind::Module
    else
      default
    end
  end
end
