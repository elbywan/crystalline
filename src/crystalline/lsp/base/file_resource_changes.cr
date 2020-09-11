require "json"
require "../tools"

module LSP
  # Options to create a file.
  class CreateFileOptions
    include Initializer
    include JSON::Serializable

    # Overwrite existing file. Overwrite wins over `ignoreIfExists`
    property overwrite : Bool?
    # Ignore if exists.
    @[JSON::Field(key: "ignoreIfExists")]
    property ignore_if_exists : Bool?
  end

  # Create file operation
  class CreateFile
    include Initializer
    include JSON::Serializable

    # A create
    @kind : String = "create"
    # The resource to create.
    property uri : String
    # Additional options
    property options : CreateFileOptions?
  end

  # Rename file options
  class RenameFileOptions
    include Initializer
    include JSON::Serializable

    # Overwrite target if existing. Overwrite wins over `ignoreIfExists`
    property overwrite : Bool?
    @[JSON::Field(key: "ignoreIfExists")]
    property ignore_if_exists : Bool?
  end

  # Rename file operation
  class RenameFile
    include Initializer
    include JSON::Serializable

    # A rename
    @kind : String = "rename"
    # The old (existing) location.
    @[JSON::Field(key: "oldUri")]
    property old_url : String

    # The new location.
    @[JSON::Field(key: "newUri")]
    property new_uri : String

    # Rename options.
    property options : RenameFileOptions?
  end

  # Delete file options
  class DeleteFileOptions
    include Initializer
    include JSON::Serializable

    # Delete the content recursively if a folder is denoted.
    property recursive : Bool?

    # Ignore the operation if the file doesn't exist.
    @[JSON::Field(key: "ignoreIfNotExists")]
    property ignore_if_not_exists : Bool?
  end

  # Delete file operation
  class DeleteFile
    include Initializer
    include JSON::Serializable

    # A delete
    @kind = "delete"

    # The file to delete.
    property uri : String

    # Delete options.
    property options : DeleteFileOptions?
  end
end
