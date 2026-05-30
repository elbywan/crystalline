class LSP::Server
  private def serial_notification?(message : LSP::NotificationMessage) : Bool
    message.is_a?(LSP::DidOpenNotification) ||
      message.is_a?(LSP::DidChangeNotification) ||
      message.is_a?(LSP::DidCloseNotification) ||
      message.is_a?(LSP::DidSaveNotification)
  end

  private def delegate(controller, message : LSP::NotificationMessage)
    if serial_notification?(message)
      if controller.responds_to? :on_notification
        controller.on_notification(message)
      end
    else
      previous_def
    end
  rescue e
    on_exception(message, e)
  end
end
