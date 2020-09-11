require "json"
require "../../tools"
require "../../base/*"
require "../request_message"
require "../../notifications/text_synchronization/will_save"

module LSP
  # The document will save request is sent from the client to the server before the document is actually saved.
  # The request can return an array of TextEdits which will be applied to the text document before it is saved.
  # Please note that clients might drop results if computing the text edits took too long or if a server constantly fails on this request.
  # This is done to keep the save fast and reliable.
  class WillSaveWaitUntilRequest < RequestMessage(Array(TextEdit)?)
    @method = "textDocument/willSaveWaitUntil"
    property params : WillSaveTextDocumentParams
  end
end
