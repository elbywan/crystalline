require "digest"

class Crystalline < Formula
  desc "A Language Server Protocol implementation for Crystal. "
  homepage "https://github.com/elbywan/crystalline"
  url "https://github.com/elbywan/crystalline/archive/v0.5.0.tar.gz"
  sha256 "b7a203d0e5d4e37bbe744b371fca77868aca8f71"

  depends_on "crystal"

  def install
    # TODO: How to specify LLVM_CONFIG value via depends on or at install time
    system "make", "install", "PREFIX=#{prefix}"
  end

  test do
    # TODO
  end
end
