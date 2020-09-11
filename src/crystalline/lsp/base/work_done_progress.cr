require "json"
require "../tools"
require "../notifications/progress"

module LSP
  # Work done progress is reported using the generic $/progress notification.
  # The value payload of a work done progress notification can be of three different forms.

  # To start progress reporting a $/progress notification with the following payload must be sent.
  struct WorkDoneProgressBegin
    include Initializer
    include JSON::Serializable

    @kind = "begin"

    # Mandatory title of the progress operation. Used to briefly inform about
    # the kind of operation being performed.
    #
    # Examples: "Indexing" or "Linking dependencies".
    property title : String
    # Controls if a cancel button should show to allow the user to cancel the
    # long running operation. Clients that don't support cancellation are allowed
    # to ignore the setting.
    property cancellable : Bool?
    # Optional, more detailed associated progress message. Contains
    # complementary information to the `title`.
    #
    # Examples: "3/25 files", "project/src/module2", "node_modules/some_dep".
    # If unset, the previous progress message (if any) is still valid.
    property message : String?
    # Optional progress percentage to display (value 100 is considered 100%).
    # If not provided infinite progress is assumed and clients are allowed
    # to ignore the `percentage` value in subsequent in report notifications.
    #
    # The value should be steadily rising. Clients are free to ignore values
    # that are not following this rule.
    property percentage : Int32?
  end

  # Reporting progress is done using the following payload.
  struct WorkDoneProgressReport
    include Initializer
    include JSON::Serializable

    @kind = "report"

    # Controls enablement state of a cancel button. This property is only valid if a cancel
    # button got requested in the `WorkDoneProgressStart` payload.
    #
    # Clients that don't support cancellation or don't support control the button's
    # enablement state are allowed to ignore the setting.
    property cancellable : Bool?

    # Optional, more detailed associated progress message. Contains
    # complementary information to the `title`.
    #
    # Examples: "3/25 files", "project/src/module2", "node_modules/some_dep".
    # If unset, the previous progress message (if any) is still valid.
    property message : String?

    # Optional progress percentage to display (value 100 is considered 100%).
    # If not provided infinite progress is assumed and clients are allowed
    # to ignore the `percentage` value in subsequent in report notifications.
    #
    # The value should be steadily rising. Clients are free to ignore values
    # that are not following this rule.
    property percentage : Int32?
  end

  # Signaling the end of a progress reporting is done using the following payload.
  struct WorkDoneProgressEnd
    include Initializer
    include JSON::Serializable

    @kind = "end"

    # Optional, a final message indicating to for example indicate the outcome
    # of the operation.
    property message : String?
  end

  # A parameter literal used to pass a work done progress token.
  module WorkDoneProgressParams
    # An optional token that a server can use to report work done progress.
    @[JSON::Field(key: "workDoneToken")]
    property work_done_token : ProgressToken?
  end

  # Options to signal work done progress support in server capabilities.
  module WorkDoneProgressOptions
    @[JSON::Field(key: "workDoneProgress")]
    property work_done_progress : Bool?
  end
end
