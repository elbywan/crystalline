require "yaml"

class Crystalline::Project
  class ProjectFile
    include YAML::Serializable

    getter projects : Array(String) = [] of String
  end

  # The project root filesystem uri.
  getter root_uri : URI
  # The dependencies of the project, meaning the list of files required by the compilation target (entry point).
  property dependencies : Set(String) = Set(String).new
  # Determines the project entry point.
  getter? entry_point : URI? do
    path = Path[root_uri.decoded_path, "shard.yml"]
    shards_yaml = File.open(path) do |file|
      YAML.parse(file)
    end
    shard_name = shards_yaml["name"].as_s
    # If shard.yml has the `crystalline/main` key, use that.
    relative_main = shards_yaml.dig?("crystalline", "main").try &.as_s
    # Else if shard.yml has a `targets/[shard name]/main` key, use that.
    relative_main ||= shards_yaml.dig?("targets", shard_name, "main").try &.as_s
    if relative_main && File.exists? Path[root_uri.decoded_path, relative_main]
      main_path = Path[root_uri.decoded_path, relative_main]
      # Add the entry point as a dependency to itself.
      dependencies << main_path.to_s
      URI.parse("file://#{main_path}")
    end
  rescue e
    nil
  end

  def initialize(@root_uri)
  end

  # Finds and returns an array of all projects in the workspace root.
  def self.find_in_workspace_root(workspace_root_uri : URI) : Array(Project)
    # First, check for a Crystalline project file.
    begin
      crystalline_path = Path[workspace_root_uri.decoded_path, ".crystalline.yml"]
      crystalline_file = File.open(crystalline_path) do |file|
        ProjectFile.from_yaml(file)
      end

      crystalline_file.projects.map do |p|
        path = Path[workspace_root_uri.decoded_path, p].normalize
        Project.new(URI.parse("file://#{path}"))
      end
    rescue e
      # Failing that, create a project for the workspace root.
      [Project.new(workspace_root_uri)]
    end
  end

  # Finds the path-wise distance to the given file URI. If the file URI is not a
  # dependency of this workspace's entry point, returns nil.
  def distance_to_dependency(file_uri : URI) : Int32?
    file_path = file_uri.decoded_path
    return nil if !file_path.in?(dependencies)

    relative = Path[file_uri.decoded_path].relative_to?(root_uri.decoded_path)
    # If we can't get a relative path, give it the maximum distance possible, so
    # it's the lowest priority.
    return Int32::MAX if relative.nil?

    relative.parts.size
  end

  # Path to the shards "lib" path for this project.
  def default_lib_path
    Path[@root_uri.decoded_path, "lib"].to_s
  end

  # Finds the best-fitting project to use for the given file.
  def self.best_fit_for_file(projects : Array(Project), file_uri : URI) : Project?
    project_distances = projects.compact_map do |p|
      distance = p.distance_to_dependency(file_uri)
      {p, distance} if distance
    end

    project_distances.sort_by(&.[1]).first?.try(&.[0])
  end
end
