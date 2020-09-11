# require "../models/progress"

# class Crystalline::Controller
#   def on_notification(message : LSP::NotificationMessage) : Nil
#     case message
#     when LSP::DidOpenNotification
#       workspace.open_document(message.params)
#     when LSP::DidChangeNotification
#       params = message.params.as(LSP::DidChangeTextDocumentParams)
#       workspace.update_document(params)
#     when LSP::DidCloseNotification
#       workspace.close_document(message.params)
#     when LSP::DidSaveNotification
#       file_uri = URI.parse message.params.text_document.uri
#       if workspace.entry_point && workspace.dependencies.size > 0 && file_uri.path.in?(workspace.dependencies)
#         workspace.compile(@server)
#       else
#         progress = Progress.new(
#           token: "analysis/compile",
#           title: "Analyzing",
#           message: file_uri.to_s
#         )
#         progress.report(@server) do
#           if Analysis.compile(@server, file_uri)
#             "Completed successfully."
#           else
#             "Completed with errors."
#           end
#         end
#       end
#     end

#     previous_def
#   end
# end
