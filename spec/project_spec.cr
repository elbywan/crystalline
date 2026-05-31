require "spec"
require "file_utils"
require "../src/crystalline/project"

describe Crystalline::Project do
  it "does not match unrelated files once dependencies are known" do
    root = File.join(Dir.tempdir, "crystalline-project-spec-#{Random::Secure.hex(8)}")
    begin
      Dir.mkdir_p(root)
      project = Crystalline::Project.new(URI.parse("file://#{root}"))
      dependency_path = File.join(root, "src", "main.cr")
      unrelated_path = File.join(root, "scratch.cr")
      Dir.mkdir_p(File.dirname(dependency_path))
      File.write(dependency_path, "")
      File.write(unrelated_path, "")

      project.dependencies << dependency_path

      Crystalline::Project.best_fit_for_file([project], URI.parse("file://#{dependency_path}")).should eq(project)
      Crystalline::Project.best_fit_for_file([project], URI.parse("file://#{unrelated_path}")).should be_nil
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
