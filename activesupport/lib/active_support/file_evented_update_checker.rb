require 'listen'
require 'set'
require 'pathname'

module ActiveSupport
  class FileEventedUpdateChecker #:nodoc: all
    def initialize(files, dirs={}, &block)
      @ph    = PathHelper.new
      @files = files.map {|f| @ph.xpath(f)}.to_set

      @dirs = {}
      dirs.each do |dir, exts|
        @dirs[@ph.xpath(dir)] = Array(exts).map {|ext| @ph.normalize_extension(ext)}
      end

      @block   = block
      @updated = false
      @lcsp    = @ph.longest_common_subpath(@dirs.keys)

      if (dtw = directories_to_watch).any?
        Listen.to(*dtw, &method(:changed)).start
      end
    end

    def updated?
      @updated
    end

    def execute
      @block.call
    ensure
      @updated = false
    end

    def execute_if_updated
      if updated?
        execute
        true
      end
    end

    private

      def changed(modified, added, removed)
        unless updated?
          @updated = (modified + added + removed).any? {|f| watching?(f)}
        end
      end

      def watching?(file)
        file = @ph.xpath(file)

        return true  if @files.member?(file)
        return false if file.directory?

        ext = @ph.normalize_extension(file.extname)
        dir = file.dirname

        loop do
          if @dirs.fetch(dir, []).include?(ext)
            break true
          else
            if @lcsp
              break false if dir == @lcsp
            else
              break false if dir.root?
            end

            dir = dir.parent
          end
        end
      end

      def directories_to_watch
        bd = []

        bd.concat @files.map {|f| @ph.existing_parent(f.dirname)}
        bd.concat @dirs.keys.map {|dir| @ph.existing_parent(dir)}
        bd.compact!
        bd.uniq!

        @ph.filter_out_descendants(bd)
      end

    class PathHelper
      using Module.new {
        refine Pathname do
          def ascendant_of?(other)
            other.to_s =~ /\A#{Regexp.quote(to_s)}#{Pathname::SEPARATOR_PAT}?/
          end
        end
      }

      def xpath(path)
        Pathname.new(path).expand_path
      end

      def normalize_extension(ext)
        ext.to_s.sub(/\A\./, '')
      end

      # Given a collection of Pathname objects returns the longest subpath
      # common to all of them, or +nil+ if there is none.
      def longest_common_subpath(paths)
        return if paths.empty?

        lcsp = Pathname.new(paths[0])

        paths[1..-1].each do |path|
          until lcsp.ascendant_of?(path)
            if lcsp.root?
              # If we get here a root directory is not an ascendant of path.
              # This may happen if there are paths in different drives on
              # Windows.
              return
            else
              lcsp = lcsp.parent
            end
          end
        end

        lcsp
      end

      # Returns the deepest existing ascendant, which could be the argument itself.
      def existing_parent(dir)
        dir.ascend do |ascendant|
          break ascendant if ascendant.directory?
        end
      end

      # Filters out directories which are descendants of others in the collection (stable).
      def filter_out_descendants(directories)
        return directories if directories.length < 2

        sorted_by_nparts = directories.sort_by {|dir| dir.each_filename.to_a.length}
        descendants = []

        until sorted_by_nparts.empty?
          dir = sorted_by_nparts.shift

          descendants.concat sorted_by_nparts.select { |possible_descendant|
            dir.ascendant_of?(possible_descendant)
          }
        end

        directories - descendants
      end
    end
  end
end
