require "./message"
require "./requests/request_message"

module LSP
  struct ResponseMessage(Result)
    include Message
    include Initializer
    include JSON::Serializable
    include JSON::Serializable::Strict

    # The request id.
    property id : RequestMessage::RequestId?

    # The result of a request. This member is REQUIRED on success.
    # This member MUST NOT exist if there was an error invoking the method.
    @[JSON::Field(emit_null: true)]
    property result : Result?
    # The error object in case a request fails.
    property error : ResponseError?
  end

  struct ResponseError
    include Initializer
    include JSON::Serializable

    alias DataType = (String | Array(String) | Int32 | Int64 | JSON::Any)?

    # A number indicating the error type that occurred.
    property code : Int32
    # A string providing a short description of the error.
    property message : String
    # A primitive or structured value that contains additional
    # information about the error. Can be omitted.
    property data : DataType

    def initialize(e : ::LSP::Exception)
      @code = e.code.value
      @message = e.message
      @data = e.backtrace?
    end

    def initialize(e : ::Exception)
      @code = ErrorCodes::UnknownErrorCode.value
      @message = e.message || "Unknown error"
      @data = e.backtrace?
    end
  end

  enum ErrorCodes
    # Defined by JSON RPC
    ParseError           = -32700
    InvalidRequest       = -32600
    MethodNotFound       = -32601
    InvalidParams        = -32602
    InternalError        = -32603
    ServerErrorStart     = -32099
    ServerErrorEnd       = -32000
    ServerNotInitialized = -32002
    UnknownErrorCode     = -32001

    # Defined by the protocol.
    RequestCancelled = -32800
    ContentModified  = -32801
  end

  class Exception < ::Exception
    getter code : ErrorCodes = ErrorCodes::UnknownErrorCode

    def initialize(@code : ErrorCodes = UnknownErrorCode, @message : String? = nil, @cause : Exception? = nil)
    end
  end
end
