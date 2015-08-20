require 'stringio'

require 'active_support/inflector'
require 'action_dispatch/http/headers'
require 'action_controller/metal/exceptions'
require 'rack/request'
require 'action_dispatch/http/cache'
require 'action_dispatch/http/mime_negotiation'
require 'action_dispatch/http/parameters'
require 'action_dispatch/http/filter_parameters'
require 'action_dispatch/http/upload'
require 'action_dispatch/http/url'
require 'active_support/core_ext/array/conversions'

module ActionDispatch
  class Request < Rack::Request
    include ActionDispatch::Http::Cache::Request
    include ActionDispatch::Http::MimeNegotiation
    include ActionDispatch::Http::Parameters
    include ActionDispatch::Http::FilterParameters
    include ActionDispatch::Http::URL

    HTTP_X_REQUEST_ID = "HTTP_X_REQUEST_ID".freeze # :nodoc:

    autoload :Session, 'action_dispatch/request/session'
    autoload :Utils,   'action_dispatch/request/utils'

    LOCALHOST   = Regexp.union [/^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, /^::1$/, /^0:0:0:0:0:0:0:1(%.*)?$/]

    ENV_METHODS = %w[ AUTH_TYPE GATEWAY_INTERFACE
        PATH_TRANSLATED REMOTE_HOST
        REMOTE_IDENT REMOTE_USER REMOTE_ADDR
        SERVER_NAME SERVER_PROTOCOL

        HTTP_ACCEPT HTTP_ACCEPT_CHARSET HTTP_ACCEPT_ENCODING
        HTTP_ACCEPT_LANGUAGE HTTP_CACHE_CONTROL HTTP_FROM
        HTTP_NEGOTIATE HTTP_PRAGMA HTTP_CLIENT_IP
        HTTP_X_FORWARDED_FOR HTTP_VERSION
        ].freeze

    ENV_METHODS.each do |env|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def #{env.sub(/^HTTP_/n, '').downcase}  # def accept_charset
          @env["#{env}".freeze]                 #   @env["HTTP_ACCEPT_CHARSET".freeze]
        end                                     # end
      METHOD
    end

    def initialize(env)
      super
      @method            = nil
      @request_method    = nil
      @remote_ip         = nil
      @original_fullpath = nil
      @fullpath          = nil
      @ip                = nil
    end

    def check_path_parameters!
      # If any of the path parameters has an invalid encoding then
      # raise since it's likely to trigger errors further on.
      path_parameters.each do |key, value|
        next unless value.respond_to?(:valid_encoding?)
        unless value.valid_encoding?
          raise ActionController::BadRequest, "Invalid parameter: #{key} => #{value}"
        end
      end
    end

    def key?(key)
      @env.key?(key)
    end

    # List of HTTP request methods from the following RFCs:
    # Hypertext Transfer Protocol -- HTTP/1.1 (http://www.ietf.org/rfc/rfc2616.txt)
    # HTTP Extensions for Distributed Authoring -- WEBDAV (http://www.ietf.org/rfc/rfc2518.txt)
    # Versioning Extensions to WebDAV (http://www.ietf.org/rfc/rfc3253.txt)
    # Ordered Collections Protocol (WebDAV) (http://www.ietf.org/rfc/rfc3648.txt)
    # Web Distributed Authoring and Versioning (WebDAV) Access Control Protocol (http://www.ietf.org/rfc/rfc3744.txt)
    # Web Distributed Authoring and Versioning (WebDAV) SEARCH (http://www.ietf.org/rfc/rfc5323.txt)
    # Calendar Extensions to WebDAV (http://www.ietf.org/rfc/rfc4791.txt)
    # PATCH Method for HTTP (http://www.ietf.org/rfc/rfc5789.txt)
    RFC2616 = %w(OPTIONS GET HEAD POST PUT DELETE TRACE CONNECT)
    RFC2518 = %w(PROPFIND PROPPATCH MKCOL COPY MOVE LOCK UNLOCK)
    RFC3253 = %w(VERSION-CONTROL REPORT CHECKOUT CHECKIN UNCHECKOUT MKWORKSPACE UPDATE LABEL MERGE BASELINE-CONTROL MKACTIVITY)
    RFC3648 = %w(ORDERPATCH)
    RFC3744 = %w(ACL)
    RFC5323 = %w(SEARCH)
    RFC4791 = %w(MKCALENDAR)
    RFC5789 = %w(PATCH)

    HTTP_METHODS = RFC2616 + RFC2518 + RFC3253 + RFC3648 + RFC3744 + RFC5323 + RFC4791 + RFC5789

    HTTP_METHOD_LOOKUP = {}

    # Populate the HTTP method lookup cache
    HTTP_METHODS.each { |method|
      HTTP_METHOD_LOOKUP[method] = method.underscore.to_sym
    }

    # Returns the HTTP \method that the application should see.
    # In the case where the \method was overridden by a middleware
    # (for instance, if a HEAD request was converted to a GET,
    # or if a _method parameter was used to determine the \method
    # the application should use), this \method returns the overridden
    # value, not the original.
    def request_method
      @request_method ||= check_method(super)
    end

    def routes # :nodoc:
      env["action_dispatch.routes".freeze]
    end

    def routes=(routes) # :nodoc:
      env["action_dispatch.routes".freeze] = routes
    end

    def original_script_name # :nodoc:
      env['ORIGINAL_SCRIPT_NAME'.freeze]
    end

    def engine_script_name(_routes) # :nodoc:
      env[_routes.env_key]
    end

    def engine_script_name=(name) # :nodoc:
      env[routes.env_key] = name.dup
    end

    def request_method=(request_method) #:nodoc:
      if check_method(request_method)
        @request_method = env["REQUEST_METHOD"] = request_method
      end
    end

    def controller_instance # :nodoc:
      env['action_controller.instance'.freeze]
    end

    def controller_instance=(controller) # :nodoc:
      env['action_controller.instance'.freeze] = controller
    end

    def show_exceptions? # :nodoc:
      # We're treating `nil` as "unset", and we want the default setting to be
      # `true`.  This logic should be extracted to `env_config` and calculated
      # once.
      !(env['action_dispatch.show_exceptions'.freeze] == false)
    end

    # Returns a symbol form of the #request_method
    def request_method_symbol
      HTTP_METHOD_LOOKUP[request_method]
    end

    # Returns the original value of the environment's REQUEST_METHOD,
    # even if it was overridden by middleware. See #request_method for
    # more information.
    def method
      @method ||= check_method(env["rack.methodoverride.original_method"] || env['REQUEST_METHOD'])
    end

    # Returns a symbol form of the #method
    def method_symbol
      HTTP_METHOD_LOOKUP[method]
    end

    # Provides access to the request's HTTP headers, for example:
    #
    #   request.headers["Content-Type"] # => "text/plain"
    def headers
      @headers ||= Http::Headers.new(self)
    end

    # Returns a +String+ with the last requested path including their params.
    #
    #    # get '/foo'
    #    request.original_fullpath # => '/foo'
    #
    #    # get '/foo?bar'
    #    request.original_fullpath # => '/foo?bar'
    def original_fullpath
      @original_fullpath ||= (env["ORIGINAL_FULLPATH"] || fullpath)
    end

    # Returns the +String+ full path including params of the last URL requested.
    #
    #    # get "/articles"
    #    request.fullpath # => "/articles"
    #
    #    # get "/articles?page=2"
    #    request.fullpath # => "/articles?page=2"
    def fullpath
      @fullpath ||= super
    end

    # Returns the original request URL as a +String+.
    #
    #    # get "/articles?page=2"
    #    request.original_url # => "http://www.example.com/articles?page=2"
    def original_url
      base_url + original_fullpath
    end

    # The +String+ MIME type of the request.
    #
    #    # get "/articles"
    #    request.media_type # => "application/x-www-form-urlencoded"
    def media_type
      content_mime_type.to_s
    end

    # Returns the content length of the request as an integer.
    def content_length
      super.to_i
    end

    # Returns true if the "X-Requested-With" header contains "XMLHttpRequest"
    # (case-insensitive), which may need to be manually added depending on the
    # choice of JavaScript libraries and frameworks.
    def xml_http_request?
      @env['HTTP_X_REQUESTED_WITH'] =~ /XMLHttpRequest/i
    end
    alias :xhr? :xml_http_request?

    # Returns the IP address of client as a +String+.
    def ip
      @ip ||= super
    end

    # Returns the IP address of client as a +String+,
    # usually set by the RemoteIp middleware.
    def remote_ip
      @remote_ip ||= (@env["action_dispatch.remote_ip"] || ip).to_s
    end

    def remote_ip=(remote_ip)
      @env["action_dispatch.remote_ip".freeze] = remote_ip
    end

    ACTION_DISPATCH_REQUEST_ID = "action_dispatch.request_id".freeze # :nodoc:

    # Returns the unique request id, which is based on either the X-Request-Id header that can
    # be generated by a firewall, load balancer, or web server or by the RequestId middleware
    # (which sets the action_dispatch.request_id environment variable).
    #
    # This unique ID is useful for tracing a request from end-to-end as part of logging or debugging.
    # This relies on the rack variable set by the ActionDispatch::RequestId middleware.
    def request_id
      env[ACTION_DISPATCH_REQUEST_ID]
    end

    def request_id=(id) # :nodoc:
      env[ACTION_DISPATCH_REQUEST_ID] = id
    end

    alias_method :uuid, :request_id

    def x_request_id # :nodoc:
      @env[HTTP_X_REQUEST_ID]
    end

    # Returns the lowercase name of the HTTP server software.
    def server_software
      (@env['SERVER_SOFTWARE'] && /^([a-zA-Z]+)/ =~ @env['SERVER_SOFTWARE']) ? $1.downcase : nil
    end

    # Read the request \body. This is useful for web services that need to
    # work with raw requests directly.
    def raw_post
      unless @env.include? 'RAW_POST_DATA'
        raw_post_body = body
        @env['RAW_POST_DATA'] = raw_post_body.read(content_length)
        raw_post_body.rewind if raw_post_body.respond_to?(:rewind)
      end
      @env['RAW_POST_DATA']
    end

    # The request body is an IO input stream. If the RAW_POST_DATA environment
    # variable is already set, wrap it in a StringIO.
    def body
      if raw_post = @env['RAW_POST_DATA']
        raw_post.force_encoding(Encoding::BINARY)
        StringIO.new(raw_post)
      else
        @env['rack.input']
      end
    end

    # Returns true if the request's content MIME type is
    # +application/x-www-form-urlencoded+ or +multipart/form-data+.
    def form_data?
      FORM_DATA_MEDIA_TYPES.include?(content_mime_type.to_s)
    end

    def body_stream #:nodoc:
      @env['rack.input']
    end

    # TODO This should be broken apart into AD::Request::Session and probably
    # be included by the session middleware.
    def reset_session
      if session && session.respond_to?(:destroy)
        session.destroy
      else
        self.session = {}
      end
      @env['action_dispatch.request.flash_hash'] = nil
    end

    def session=(session) #:nodoc:
      Session.set @env, session
    end

    def session_options=(options)
      Session::Options.set @env, options
    end

    # Override Rack's GET method to support indifferent access
    def GET
      @env["action_dispatch.request.query_parameters"] ||= normalize_encode_params(super || {})
    rescue Rack::Utils::ParameterTypeError, Rack::Utils::InvalidParameterError => e
      raise ActionController::BadRequest.new(:query, e)
    end
    alias :query_parameters :GET

    # Override Rack's POST method to support indifferent access
    def POST
      @env["action_dispatch.request.request_parameters"] ||= normalize_encode_params(super || {})
    rescue Rack::Utils::ParameterTypeError, Rack::Utils::InvalidParameterError => e
      raise ActionController::BadRequest.new(:request, e)
    end
    alias :request_parameters :POST

    # Returns the authorization header regardless of whether it was specified directly or through one of the
    # proxy alternatives.
    def authorization
      @env['HTTP_AUTHORIZATION']   ||
      @env['X-HTTP_AUTHORIZATION'] ||
      @env['X_HTTP_AUTHORIZATION'] ||
      @env['REDIRECT_X_HTTP_AUTHORIZATION']
    end

    # True if the request came from localhost, 127.0.0.1.
    def local?
      LOCALHOST =~ remote_addr && LOCALHOST =~ remote_ip
    end

    def request_parameters=(params)
      env["action_dispatch.request.request_parameters".freeze] = params
    end

    def logger
      env["action_dispatch.logger".freeze]
    end

    private
      def check_method(name)
        HTTP_METHOD_LOOKUP[name] || raise(ActionController::UnknownHttpMethod, "#{name}, accepted HTTP methods are #{HTTP_METHODS[0...-1].join(', ')}, and #{HTTP_METHODS[-1]}")
        name
      end
  end
end
