class URI
  @decoded_path : String? = nil

  def decoded_path : String
    @decoded_path ||= URI.decode(@path)
  end

  def path=(path : String) : Nil
    @decoded_path = nil
    @path = path
  end
end
