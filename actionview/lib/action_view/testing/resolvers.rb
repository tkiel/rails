# frozen_string_literal: true

require "action_view/template/resolver"

module ActionView #:nodoc:
  # Use FixtureResolver in your tests to simulate the presence of files on the
  # file system. This is used internally by Rails' own test suite, and is
  # useful for testing extensions that have no way of knowing what the file
  # system will look like at runtime.
  class FixtureResolver < PathResolver
    def initialize(hash = {}, pattern = nil)
      super(pattern)
      @hash = hash
    end

    def data
      @hash
    end

    def to_s
      @hash.keys.join(", ")
    end

    private

      def query(path, exts, _, locals, cache:)
        query = +""
        EXTENSIONS.each do |ext, prefix|
          query << "(" << exts[ext].map { |e| e && Regexp.escape("#{prefix}#{e}") }.join("|") << "|)"
        end
        query = /^(#{Regexp.escape(path)})#{query}$/

        templates = []
        @hash.each do |_path, source|
          next unless query.match?(_path)
          handler, format, variant = extract_handler_and_format_and_variant(_path)
          templates << Template.new(source, _path, handler,
            virtual_path: path.virtual,
            format: format,
            variant: variant,
            locals: locals
          )
        end

        templates.sort_by { |t| -t.identifier.match(/^#{query}$/).captures.reject(&:blank?).size }
      end
  end

  class NullResolver < PathResolver
    def query(path, exts, _, locals, cache:)
      handler, format, variant = extract_handler_and_format_and_variant(path)
      [ActionView::Template.new("Template generated by Null Resolver", path.virtual, handler, virtual_path: path.virtual, format: format, variant: variant, locals: locals)]
    end
  end
end
