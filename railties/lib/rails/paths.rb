module Rails
  module Paths
    # This object is an extended hash that behaves as root of the <tt>Rails::Paths</tt> system.
    # It allows you to collect information about how you want to structure your application
    # paths by a Hash like API. It requires you to give a physical path on initialization.
    #
    #   root = Root.new "/rails"
    #   root.add "app/controllers", autoload: true
    #
    # The command above creates a new root object and add "app/controllers" as a path.
    # This means we can get a <tt>Rails::Paths::Path</tt> object back like below:
    #
    #   path = root["app/controllers"]
    #   path.autoload?                 # => true
    #   path.is_a?(Rails::Paths::Path) # => true
    #
    # The +Path+ object is simply an enumerable and allows you to easily add extra paths:
    #
    #   path.is_a?(Enumerable) # => true
    #   path.to_ary.inspect    # => ["app/controllers"]
    #
    #   path << "lib/controllers"
    #   path.to_ary.inspect    # => ["app/controllers", "lib/controllers"]
    #
    # Notice that when you add a path using +add+, the path object created already
    # contains the path with the same path value given to +add+. In some situations,
    # you may not want this behavior, so you can give :with as option.
    #
    #   root.add "config/routes", with: "config/routes.rb"
    #   root["config/routes"].inspect # => ["config/routes.rb"]
    #
    # The +add+ method accepts the following options as arguments:
    # autoload, autoload_once and glob.
    #
    # Finally, the +Path+ object also provides a few helpers:
    #
    #   root = Root.new "/rails"
    #   root.add "app/controllers"
    #
    #   root["app/controllers"].expanded # => ["/rails/app/controllers"]
    #   root["app/controllers"].existent # => ["/rails/app/controllers"]
    #
    # Check the <tt>Rails::Paths::Path</tt> documentation for more information.
    class Root
      attr_accessor :path

      def initialize(path)
        @current = nil
        @path = path
        @root = {}
      end

      def []=(path, value)
        glob = self[path] ? self[path].glob : nil
        add(path, with: value, glob: glob)
      end

      def add(path, options = {})
        with = Array(options.fetch(:with, path))
        @root[path] = Path.new(self, path, with, options)
      end

      def [](path)
        @root[path]
      end

      def values
        @root.values
      end

      def keys
        @root.keys
      end

      def values_at(*list)
        @root.values_at(*list)
      end

      def all_paths
        values.tap { |v| v.uniq! }
      end

      def autoload_once
        filter_by(:autoload_once?)
      end

      def eager_load
        ActiveSupport::Deprecation.warn "eager_load is deprecated and all autoload_paths are now eagerly loaded."
        filter_by(:autoload?)
      end

      def autoload_paths
        filter_by(:autoload?)
      end

      def load_paths
        filter_by(:load_path?)
      end

    protected

      def filter_by(constraint)
        all = []
        all_paths.each do |path|
          if path.send(constraint)
            paths  = path.existent
            paths -= path.children.map { |p| p.send(constraint) ? [] : p.existent }.flatten
            all.concat(paths)
          end
        end
        all.uniq!
        all
      end
    end

    class Path
      include Enumerable

      attr_accessor :glob

      def initialize(root, current, paths, options = {})
        @paths    = paths
        @current  = current
        @root     = root
        @glob     = options[:glob]

        options[:autoload_once] ? autoload_once! : skip_autoload_once!
        options[:autoload]      ? autoload!      : skip_autoload!
        options[:load_path]     ? load_path!     : skip_load_path!

        if !options.key?(:autoload) && options.key?(:eager_load)
          ActiveSupport::Deprecation.warn "the :eager_load option is deprecated and all :autoload paths are now eagerly loaded."
          options[:eager_load] ? autoload! : skip_autoload!
        end
      end

      def children
        keys = @root.keys.select { |k| k.include?(@current) }
        keys.delete(@current)
        @root.values_at(*keys.sort)
      end

      def first
        expanded.first
      end

      def last
        expanded.last
      end

      %w(autoload_once autoload load_path).each do |m|
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{m}!        # def autoload!
            @#{m} = true   #   @autoload = true
          end              # end
                           #
          def skip_#{m}!   # def skip_autoload!
            @#{m} = false  #   @autoload = false
          end              # end
                           #
          def #{m}?        # def autoload?
            @#{m}          #   @autoload
          end              # end
        RUBY
      end

      def eager_load!
        ActiveSupport::Deprecation.warn "eager_load paths are deprecated and all autoload paths are now eagerly loaded."
        autoload!
      end

      def skip_eager_load!
        ActiveSupport::Deprecation.warn "eager_load paths are deprecated and all autoload paths are now eagerly loaded."
        skip_autoload!
      end

      def eager_load?
        ActiveSupport::Deprecation.warn "eager_load paths are deprecated and all autoload paths are now eagerly loaded."
        autoload?
      end

      def each(&block)
        @paths.each(&block)
      end

      def <<(path)
        @paths << path
      end
      alias :push :<<

      def concat(paths)
        @paths.concat paths
      end

      def unshift(path)
        @paths.unshift path
      end

      def to_ary
        @paths
      end

      # Expands all paths against the root and return all unique values.
      def expanded
        raise "You need to set a path root" unless @root.path
        result = []

        each do |p|
          path = File.expand_path(p, @root.path)

          if @glob && File.directory?(path)
            Dir.chdir(path) do
              result.concat(Dir.glob(@glob).map { |file| File.join path, file }.sort)
            end
          else
            result << path
          end
        end

        result.uniq!
        result
      end

      # Returns all expanded paths but only if they exist in the filesystem.
      def existent
        expanded.select { |f| File.exists?(f) }
      end

      def existent_directories
        expanded.select { |d| File.directory?(d) }
      end

      alias to_a expanded
    end
  end
end
