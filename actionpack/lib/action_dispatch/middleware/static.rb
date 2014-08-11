require 'rack/utils'
require 'active_support/core_ext/uri'

module ActionDispatch
  # This middleware returns a file's contents from disk in the body response.
  # When initialized it can accept an optional 'Cache-Control' header which
  # will be set when a response containing a file's contents is delivered.
  #
  # This middleware will render the file specified in `env["PATH_INFO"]`
  # where the base path is in the +root+ directory. For example if the +root+
  # is set to `public/` then a request with `env["PATH_INFO"]` of
  # `assets/application.js` will return a response with contents of a file
  # located at `public/assets/application.js` if the file exists. If the file
  # does not exist a 404 "File not Found" response will be returned.
  class FileHandler
    def initialize(root, cache_control)
      @root          = root.chomp('/')
      @compiled_root = /^#{Regexp.escape(root)}/
      headers        = {}
      headers['Cache-Control'] = cache_control if cache_control
      @file_server = ::Rack::File.new(@root, headers)
    end

    def match?(path)
      path = unescape_path(path)
      return false unless path.valid_encoding?

      full_path = path.empty? ? @root : File.join(@root, escape_glob_chars(path))
      paths = "#{full_path}#{ext}"

      matches = Dir[paths]
      match = matches.detect { |m| File.file?(m) }
      if match
        match.sub!(@compiled_root, '')
        ::Rack::Utils.escape(match)
      end
    end

    def call(env)
      path             = env['PATH_INFO']
      gzip_file_exists = gzip_file_exists?(path)
      if gzip_file_exists && gzip_encoding_accepted?(env)
        env['PATH_INFO'] = "#{path}.gz"
        status, headers, body       = @file_server.call(env)
        headers['Content-Encoding'] = 'gzip'
        headers['Content-Type']     = content_type(path)
      else
        status, headers, body = @file_server.call(env)
      end

      headers['Vary'] = 'Accept-Encoding' if gzip_file_exists
      return [status, headers, body]
    end

    private
      def ext
        @ext ||= begin
          ext = ::ActionController::Base.default_static_extension
          "{,#{ext},/index#{ext}}"
        end
      end

      def unescape_path(path)
        URI.parser.unescape(path)
      end

      def escape_glob_chars(path)
        path.gsub(/[*?{}\[\]]/, "\\\\\\&")
      end

      def content_type(path)
        ::Rack::Mime.mime_type(::File.extname(path), 'text/plain')
      end

      def gzip_encoding_accepted?(env)
        env['HTTP_ACCEPT_ENCODING'] =~ /\bgzip\b/
      end

      def gzip_file_exists?(path)
        File.exist?(File.join(@root, "#{::Rack::Utils.unescape(path)}.gz"))
      end
  end

  # This middleware will attempt to return the contents of a file's body from
  # disk in the response.  If a file is not found on disk, the request will be
  # delegated to the application stack. This middleware is commonly initialized
  # to serve assets from a server's `public/` directory.
  #
  # This middleware verifies the path to ensure that only files
  # living in the root directory can be rendered. A request cannot
  # produce a directory traversal using this middleware. Only 'GET' and 'HEAD'
  # requests will result in a file being returned.
  class Static
    def initialize(app, path, cache_control=nil)
      @app = app
      @file_handler = FileHandler.new(path, cache_control)
    end

    def call(env)
      case env['REQUEST_METHOD']
      when 'GET', 'HEAD'
        path = env['PATH_INFO'].chomp('/')
        if match = @file_handler.match?(path)
          env["PATH_INFO"] = match
          return @file_handler.call(env)
        end
      end

      @app.call(env)
    end
  end
end
