require "./index"

module Crystalline::Lightweight
  # A disk-cached index of the standard library prelude, so that lightweight
  # queries over a single file (before the project's top-level pass finishes)
  # can still resolve stdlib receivers like `String` or `Array`.
  #
  # The index is generated once per Crystal version by compiling a trivial
  # program with top-level semantics, and cached under the user's cache
  # directory in a compact binary format. Loading the cache takes a few
  # milliseconds; generating it takes a few seconds and happens in the
  # background.
  module PreludeIndex
    @@mutex = Mutex.new
    @@index : Index? = nil
    @@loading = false

    MAGIC          = "CPLI"
    FORMAT_VERSION = 10_u8

    # Returns the prelude index, or nil while it is being generated on the
    # first run. Never blocks.
    def self.get : Index?
      @@mutex.synchronize { @@index }
    end

    # Loads the cached index, or generates it in the background. Safe to call
    # from the startup path.
    def self.ensure_loaded
      @@mutex.synchronize do
        return if @@loading
        @@loading = true
      end

      spawn do
        begin
          if index = load_from_cache
            @@mutex.synchronize { @@index = index }
            LSP::Log.info { "[prelude] loaded #{index.types.size} types from cache" }
          else
            LSP::Log.info { "[prelude] generating prelude index (first run)..." }
            if index = generate
              save_to_cache(index)
              @@mutex.synchronize { @@index = index }
              LSP::Log.info { "[prelude] generated and cached #{index.types.size} types" }
            end
          end
        rescue ex
          LSP::Log.warn(exception: ex) { "[prelude] failed: #{ex.message}" }
        ensure
          @@mutex.synchronize { @@loading = false }
        end
      end
    end

    private def self.cache_path : String
      home = ENV["HOME"]?
      cache_dir = ENV["XDG_CACHE_HOME"]? || (home ? File.join(home, ".cache") : Dir.tempdir)
      dir = File.join(cache_dir, "crystalline")
      Dir.mkdir_p(dir)
      # The prelude content depends on the indexer itself, not just the
      # Crystal version: key the cache by the LSP's own version so an
      # upgraded build regenerates instead of reusing a stale prelude.
      key = {% if Crystalline.has_constant?(:VERSION) %}
              "#{Crystal::VERSION}-#{Crystalline::VERSION}"
            {% else %}
              Crystal::VERSION
            {% end %}
      File.join(dir, "prelude_index-#{key}.bin")
    end

    private def self.load_from_cache(path : String = cache_path) : Index?
      return unless File.exists?(path)

      io = IO::Memory.new(File.read(path))
      return unless io.read_string(4) == MAGIC
      return unless io.read_bytes(UInt8) == FORMAT_VERSION

      index = Index.new
      type_count = io.read_bytes(UInt32)
      type_count.times do
        name = read_string(io)
        kind = TypeKind.from_value(io.read_bytes(UInt8))
        # Type locations let go-to-definition jump into the stdlib.
        location = read_optional_location(io)
        name_location = read_optional_location(io)
        type = TypeInfo.new(name, kind, nil, location, name_location)
        method_count = io.read_bytes(UInt32)
        method_count.times do
          method_name = read_string(io)
          return_type = read_optional_string(io)
          class_method = io.read_bytes(UInt8) == 1
          is_macro = io.read_bytes(UInt8) == 1
          args = [] of ArgInfo
          arg_count = io.read_bytes(UInt8)
          arg_count.times do
            arg_name = read_string(io)
            restriction = read_optional_string(io)
            args << ArgInfo.new(name: arg_name, restriction: restriction, splat: io.read_bytes(UInt8) == 1)
          end
          type.methods << MethodInfo.new(
            name: method_name,
            owner: name,
            args: args,
            return_type: return_type,
            class_method: class_method,
            macro: is_macro,
            free_vars: read_string_list(io),
            block_restriction: read_optional_string(io),
            # Method locations let go-to-definition jump into the stdlib.
            location: read_optional_location(io),
            double_splat: read_optional_arg(io),
            block_arg: read_optional_arg(io),
          )
        end
        parent_count = io.read_bytes(UInt32)
        parent_count.times { type.parent_types << read_string(io) }
        delegate_count = io.read_bytes(UInt32)
        delegate_count.times do
          delegate_name = read_string(io)
          type.delegates[delegate_name] = read_string(io)
        end
        if target = read_optional_string(io)
          type.forward_missing_to = target
        end
        index.types[name] = type
      end

      top_level_count = io.read_bytes(UInt32)
      top_level_count.times do
        method_name = read_string(io)
        return_type = read_optional_string(io)
        class_method = io.read_bytes(UInt8) == 1
        args = [] of ArgInfo
        arg_count = io.read_bytes(UInt8)
        arg_count.times do
          arg_name = read_string(io)
          restriction = read_optional_string(io)
          args << ArgInfo.new(name: arg_name, restriction: restriction, splat: io.read_bytes(UInt8) == 1)
        end
        index.top_level_methods << MethodInfo.new(
          name: method_name,
          owner: "::",
          args: args,
          return_type: return_type,
          class_method: class_method,
          free_vars: read_string_list(io),
          block_restriction: read_optional_string(io),
          location: read_optional_location(io),
          double_splat: read_optional_arg(io),
          block_arg: read_optional_arg(io),
        )
      end

      index
    rescue ex
      LSP::Log.warn(exception: ex) { "[prelude] cache load failed: #{ex.message}" }
      nil
    end

    private def self.save_to_cache(index : Index, path : String = cache_path)
      io = IO::Memory.new
      io << MAGIC
      io.write_bytes(FORMAT_VERSION)
      io.write_bytes(index.types.size.to_u32)

      index.types.each_value do |type|
        write_string(io, type.name)
        io.write_bytes(type.kind.value.to_u8)
        # Type locations let go-to-definition jump into the stdlib.
        write_optional_location(io, type.location)
        write_optional_location(io, type.name_location)
        io.write_bytes(type.methods.size.to_u32)
        type.methods.each do |method|
          write_string(io, method.name)
          write_optional_string(io, method.return_type)
          io.write_bytes(method.class_method ? 1_u8 : 0_u8)
          io.write_bytes(method.macro ? 1_u8 : 0_u8)
          io.write_bytes(method.args.size.to_u8)
          method.args.each do |arg|
            write_string(io, arg.name)
            write_optional_string(io, arg.restriction)
            io.write_bytes(arg.splat ? 1_u8 : 0_u8)
          end
          write_string_list(io, method.free_vars)
          write_optional_string(io, method.block_restriction)
          write_optional_location(io, method.location)
          write_optional_arg(io, method.double_splat)
          write_optional_arg(io, method.block_arg)
        end
        io.write_bytes(type.parent_types.size.to_u32)
        type.parent_types.each { |parent_name| write_string(io, parent_name) }
        io.write_bytes(type.delegates.size.to_u32)
        type.delegates.each do |delegate_name, target|
          write_string(io, delegate_name)
          write_string(io, target)
        end
        write_optional_string(io, type.forward_missing_to)
      end

      io.write_bytes(index.top_level_methods.size.to_u32)
      index.top_level_methods.each do |method|
        write_string(io, method.name)
        write_optional_string(io, method.return_type)
        io.write_bytes(method.class_method ? 1_u8 : 0_u8)
        io.write_bytes(method.args.size.to_u8)
        method.args.each do |arg|
          write_string(io, arg.name)
          write_optional_string(io, arg.restriction)
          io.write_bytes(arg.splat ? 1_u8 : 0_u8)
        end
        write_string_list(io, method.free_vars)
        write_optional_string(io, method.block_restriction)
        write_optional_location(io, method.location)
        write_optional_arg(io, method.double_splat)
        write_optional_arg(io, method.block_arg)
      end

      temp_path = "#{path}.tmp"
      File.write(temp_path, io.to_s)
      File.rename(temp_path, path)
    rescue ex
      LSP::Log.warn(exception: ex) { "[prelude] cache save failed: #{ex.message}" }
    end

    private def self.read_string(io : IO::Memory) : String
      length = io.read_bytes(UInt16)
      io.read_string(length)
    end

    private def self.read_optional_string(io : IO::Memory) : String?
      present = io.read_bytes(UInt8) == 1
      present ? read_string(io) : nil
    end

    # A source location (filename, line, column), or nothing when the
    # def carries none (macro-generated methods without a source span).
    private def self.read_optional_location(io : IO::Memory) : Crystal::Location?
      present = io.read_bytes(UInt8) == 1
      return unless present
      filename = read_string(io)
      line = io.read_bytes(UInt32).to_i32
      column = io.read_bytes(UInt32).to_i32
      Crystal::Location.new(filename, line, column)
    end

    # `**kwargs` and `&block`, which live outside `Def#args`.
    private def self.read_optional_arg(io : IO::Memory) : ArgInfo?
      present = io.read_bytes(UInt8) == 1
      return unless present

      ArgInfo.new(name: read_string(io), restriction: read_optional_string(io))
    end

    private def self.read_string_list(io : IO::Memory) : Array(String)
      count = io.read_bytes(UInt8)
      Array.new(count) { read_string(io) }
    end

    private def self.write_string(io : IO::Memory, string : String)
      io.write_bytes(string.size.to_u16)
      io << string
    end

    private def self.write_optional_string(io : IO::Memory, string : String?)
      if string
        io.write_bytes(1_u8)
        write_string(io, string)
      else
        io.write_bytes(0_u8)
      end
    end

    private def self.write_optional_location(io : IO::Memory, location : Crystal::Location?)
      if location && (filename = location.original_filename)
        io.write_bytes(1_u8)
        write_string(io, filename)
        io.write_bytes(location.line_number.to_u32)
        io.write_bytes(location.column_number.to_u32)
      else
        io.write_bytes(0_u8)
      end
    end

    private def self.write_optional_arg(io : IO::Memory, arg : ArgInfo?)
      if arg
        io.write_bytes(1_u8)
        write_string(io, arg.name)
        write_optional_string(io, arg.restriction)
      else
        io.write_bytes(0_u8)
      end
    end

    private def self.write_string_list(io : IO::Memory, strings : Array(String))
      io.write_bytes(strings.size.to_u8)
      strings.each { |string| write_string(io, string) }
    end

    # Compiles a trivial program with top-level semantics: the resulting
    # program contains the full stdlib prelude without any project code.
    # The Crystal compiler's own types (`Crystal::ASTNode`,
    # `Crystal::Compiler::Result`, ...) are not part of that prelude, so the
    # distribution's compiler sources are parsed and merged in too: projects
    # built on the compiler (like this LSP itself) would otherwise have no
    # lightweight info for those receivers until the first compile.
    def self.generate : Index?
      path = File.join(Dir.tempdir, "crystalline-prelude-#{Random::Secure.hex(8)}.cr")
      File.write(path, "puts \"hello\"\n")
      Crystalline::EnvironmentConfig.run
      server = LSP::Server.new(IO::Memory.new, IO::Memory.new)
      result = Crystalline::Analysis.compile(
        server,
        URI.parse("file://#{path}"),
        top_level: true,
        ignore_diagnostics: true,
      )
      index = result.try { |r| Index.from_program(r.program) }
      return unless index

      compiler_indexes = [] of Index
      Crystal::CrystalPath.default_path_without_lib.split(Process::PATH_DELIMITER).each do |path_entry|
        # The distribution's stdlib and compiler sources: parsing them (in
        # addition to the compiled snapshot) covers types the trivial
        # program never instantiates (`URI`, `Set`, `Channel`, ...) with
        # their full method lists.
        Dir.glob(File.join(path_entry, "**", "*.cr")).sort.each do |file|
          next if file.includes?("/compiler/")
          if file_index = Index.from_source(File.read(file), file)
            compiler_indexes << file_index
          end
        end

        compiler_dir = File.join(path_entry, "compiler")
        next unless Dir.exists?(compiler_dir)

        Dir.glob(File.join(compiler_dir, "**", "*.cr")).sort.each do |file|
          if file_index = Index.from_source(File.read(file), file)
            compiler_indexes << file_index
          end
        end
      end
      index = Index.merge([index] + compiler_indexes) unless compiler_indexes.empty?

      index
    ensure
      File.delete(path) if path && File.exists?(path)
    end

    # Test hooks: exercise the cache format with an explicit path.
    def self.save_to_cache_for_test(index : Index, path : String)
      save_to_cache(index, path)
    end

    def self.load_from_cache_for_test(path : String) : Index?
      load_from_cache(path)
    end
  end
end
