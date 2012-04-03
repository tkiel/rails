module ActiveSupport
  # \FileUpdateChecker specifies the API used by Rails to watch files
  # and control reloading. The API depends on four methods:
  #
  # * +initialize+ which expects two parameters and one block as
  #   described below;
  #
  # * +updated?+ which returns a boolean if there were updates in
  #   the filesystem or not;
  #
  # * +execute+ which executes the given block on initialization
  #   and updates the latest watched files and timestamp;
  #
  # * +execute_if_updated+ which just executes the block if it was updated;
  #
  # After initialization, a call to +execute_if_updated+ must execute
  # the block only if there was really a change in the filesystem.
  #
  # == Examples
  #
  # This class is used by Rails to reload the I18n framework whenever
  # they are changed upon a new request.
  #
  #   i18n_reloader = ActiveSupport::FileUpdateChecker.new(paths) do
  #     I18n.reload!
  #   end
  #
  #   ActionDispatch::Reloader.to_prepare do
  #     i18n_reloader.execute_if_updated
  #   end
  #
  class FileUpdateChecker
    # It accepts two parameters on initialization. The first is an array
    # of files and the second is an optional hash of directories. The hash must
    # have directories as keys and the value is an array of extensions to be
    # watched under that directory.
    #
    # This method must also receive a block that will be called once a path changes.
    #
    # == Implementation details
    #
    # This particular implementation checks for added, updated, and removed
    # files. Directories lookup are compiled to a glob for performance.
    # Therefore, while someone can add new files to the +files+ array after
    # initialization (and parts of Rails do depend on this feature), adding
    # new directories after initialization is not supported.
    #
    # Notice that other objects that implement the FileUpdateChecker API may
    # not even allow new files to be added after initialization. If this
    # is the case, we recommend freezing the +files+ after initialization to
    # avoid changes that won't make effect.
    def initialize(files, dirs={}, &block)
      @files = files
      @glob  = compile_glob(dirs)
      @block = block

      @last_watched   = watched
      @last_update_at = updated_at(@last_watched)
    end

    # Check if any of the entries were updated. If so, the watched and/or
    # updated_at values are cached until the block is executed via +execute+
    # or +execute_if_updated+
    def updated?
      current_watched = watched
      if @last_watched.size != current_watched.size
        @watched = current_watched
        true
      else
        current_updated_at = updated_at(current_watched)
        if @last_update_at < current_updated_at
          @watched    = current_watched
          @updated_at = current_updated_at
          true
        else
          false
        end
      end
    end

    # Executes the given block and updates the latest watched files and timestamp.
    def execute
      @last_watched   = watched
      @last_update_at = updated_at(@last_watched)
      @block.call
    ensure
      @watched = nil
      @updated_at = nil
    end

    # Execute the block given if updated.
    def execute_if_updated
      if updated?
        execute
        true
      else
        false
      end
    end

    private

    def watched
      @watched || begin
        all = @files.select { |f| File.exists?(f) }
        all.concat(Dir[@glob]) if @glob
        all
      end
    end

    def updated_at(paths)
      @updated_at || paths.map { |path| File.mtime(path) }.max || Time.at(0)
    end

    def compile_glob(hash)
      hash.freeze # Freeze so changes aren't accidently pushed
      return if hash.empty?

      globs = hash.map do |key, value|
        "#{escape(key)}/**/*#{compile_ext(value)}"
      end
      "{#{globs.join(",")}}"
    end

    def escape(key)
      key.gsub(',','\,')
    end

    def compile_ext(array)
      array = Array(array)
      return if array.empty?
      ".{#{array.join(",")}}"
    end
  end
end
