require "yaml"

class Crystalline::Project
  # The project root filesystem uri.
  getter root_uri : URI
  # The dependencies of the project, meaning the list of files required by the compilation target (entry point).
  property dependencies : Set(String) = Set(String).new
  # Determines the project entry point.
  getter? entry_point : URI? do
    shard_name = shard_yaml["name"].as_s
    # If shard.yml has the `crystalline/main` key, use that.
    relative_main = shard_yaml.dig?("crystalline", "main").try &.as_s
    # Else if shard.yml has a `targets/[shard name]/main` key, use that.
    relative_main ||= shard_yaml.dig?("targets", shard_name, "main").try &.as_s
    if relative_main && File.exists? Path[root_uri.decoded_path, relative_main]
      main_path = Path[root_uri.decoded_path, relative_main]
      # Add the entry point as a dependency to itself.
      dependencies << main_path.to_s
      URI.parse("file://#{main_path}")
    end
  rescue e
    nil
  end
  # Flags to pass to the underlying compiler (-Dpreview_mt, etc).
  getter flags : Array(String) do
    (shard_yaml.dig?("crystalline", "flags").try(&.as_a.map(&.as_s)) || [] of String).tap do |flags|
      LSP::Log.info { "Flags for project #{root_uri}: #{flags}" }
    end
  end

  private getter shard_yaml : YAML::Any do
    path = Path[root_uri.decoded_path, "shard.yml"]
    shards_yaml = File.open(path) do |file|
      YAML.parse(file)
    end
  end

  def initialize(@root_uri)
  end

  # Finds and returns an array of all projects in the workspace root.
  def self.find_in_workspace_root(workspace_root_uri : URI) : Array(Project)
    root_project = Project.new(workspace_root_uri)
    # First, check for a Crystalline project file.
    begin
      path = Path[workspace_root_uri.decoded_path, "shard.yml"]
      shards_yaml = File.open(path) do |file|
        YAML.parse(file)
      end

      projects = shards_yaml.dig?("crystalline", "projects").try do |pjs|
        Dir.glob(pjs.as_a.map(&.as_s)).reduce([] of Project) do |acc, match|
          path = Path.new(match)

          is_directory = File.directory?(path)
          has_shard_yml = is_directory && File.exists?(Path[path, "shard.yml"])
          is_not_lib = has_shard_yml && path.parent != "lib"

          if is_directory && has_shard_yml && is_not_lib
            normalized_path = Path[workspace_root_uri.decoded_path, path].normalize
            acc << Project.new(URI.parse("file://#{normalized_path}"))
          else
            acc
          end
        end
      end || [] of Project

      projects << root_project
    rescue e
      # Failing that, create a project for the workspace root.
      [root_project]
    end
  end

  # Finds the path-wise distance to the given file URI. If the file URI is not a
  # dependency of this workspace's entry point, returns nil.
  def distance_to_dependency(file_uri : URI) : Int32?
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
