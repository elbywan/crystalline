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
    projects = [] of Project
    root_path = workspace_root_uri.decoded_path

    # Check the root itself.
    if File.exists?(Path[root_path, "shard.yml"])
      projects << Project.new(workspace_root_uri)
    end

    # Search recursively for shard.yml files, ignoring the 'lib' folder.
    Dir.glob(Path[root_path, "**", "shard.yml"].to_s).each do |shard_path|
      path = Path[shard_path].parent
      # Skip if it's in a 'lib' directory.
      next if path.parts.includes?("lib")
      # Skip if it's the root path (already added).
      next if path.to_s == root_path

      projects << Project.new(URI.parse("file://#{path}"))
    end

    # If we found an explicit list of projects in the root shard.yml, use that instead.
    begin
      path = Path[root_path, "shard.yml"]
      shards_yaml = File.open(path) { |file| YAML.parse(file) }
      explicit_projects = shards_yaml.dig?("crystalline", "projects").try &.as_a.map(&.as_s)
      if explicit_projects
        projects = explicit_projects.reduce([] of Project) do |acc, pattern|
          Dir.glob(Path[root_path, pattern].to_s).each do |match|
            if File.directory?(match) && File.exists?(Path[match, "shard.yml"])
              acc << Project.new(URI.parse("file://#{match}"))
            end
          end
          acc
        end
        # Also include the root if it has a shard.yml.
        if File.exists?(Path[root_path, "shard.yml"])
          projects << Project.new(workspace_root_uri)
        end
      end
    rescue
      # Ignore errors and keep whatever we found.
    end

    projects.uniq!(&.root_uri.to_s)
    projects.empty? ? [Project.new(workspace_root_uri)] : projects
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
