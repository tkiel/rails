require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/string/filters'
require 'active_support/deprecation'
require 'action_dispatch/http/filter_redirect'
require 'monitor'

module ActionDispatch # :nodoc:
  # Represents an HTTP response generated by a controller action. Use it to
  # retrieve the current state of the response, or customize the response. It can
  # either represent a real HTTP response (i.e. one that is meant to be sent
  # back to the web browser) or a TestResponse (i.e. one that is generated
  # from integration tests).
  #
  # \Response is mostly a Ruby on \Rails framework implementation detail, and
  # should never be used directly in controllers. Controllers should use the
  # methods defined in ActionController::Base instead. For example, if you want
  # to set the HTTP response's content MIME type, then use
  # ActionControllerBase#headers instead of Response#headers.
  #
  # Nevertheless, integration tests may want to inspect controller responses in
  # more detail, and that's when \Response can be useful for application
  # developers. Integration test methods such as
  # ActionDispatch::Integration::Session#get and
  # ActionDispatch::Integration::Session#post return objects of type
  # TestResponse (which are of course also of type \Response).
  #
  # For example, the following demo integration test prints the body of the
  # controller response to the console:
  #
  #  class DemoControllerTest < ActionDispatch::IntegrationTest
  #    def test_print_root_path_to_console
  #      get('/')
  #      puts response.body
  #    end
  #  end
  class Response
    # The request that the response is responding to.
    attr_accessor :request

    # The HTTP status code.
    attr_reader :status

    attr_writer :sending_file

    # Get and set headers for this response.
    attr_accessor :header

    alias_method :headers=, :header=
    alias_method :headers,  :header

    delegate :[], :[]=, :to => :@header
    delegate :each, :to => :@stream

    # Sets the HTTP response's content MIME type. For example, in the controller
    # you could write this:
    #
    #  response.content_type = "text/plain"
    #
    # If a character set has been defined for this response (see charset=) then
    # the character set information will also be included in the content type
    # information.
    attr_reader   :content_type

    # The charset of the response. HTML wants to know the encoding of the
    # content you're giving them, so we need to send that along.
    attr_accessor :charset

    CONTENT_TYPE = "Content-Type".freeze
    SET_COOKIE   = "Set-Cookie".freeze
    LOCATION     = "Location".freeze
    NO_CONTENT_CODES = [204, 304]

    cattr_accessor(:default_charset) { "utf-8" }
    cattr_accessor(:default_headers)

    include Rack::Response::Helpers
    include ActionDispatch::Http::FilterRedirect
    include ActionDispatch::Http::Cache::Response
    include MonitorMixin

    class Buffer # :nodoc:
      def initialize(response, buf)
        @response = response
        @buf      = buf
        @closed   = false
      end

      def write(string)
        raise IOError, "closed stream" if closed?

        @response.commit!
        @buf.push string
      end

      def each(&block)
        @response.sending!
        x = @buf.each(&block)
        @response.sent!
        x
      end

      def abort
      end

      def close
        @response.commit!
        @closed = true
      end

      def closed?
        @closed
      end
    end

    # The underlying body, as a streamable object.
    attr_reader :stream

    def initialize(status = 200, header = {}, body = [])
      super()

      header = merge_default_headers(header, self.class.default_headers)

      self.body, self.header, self.status = body, header, status

      @sending_file = false
      @blank        = false
      @cv           = new_cond
      @committed    = false
      @sending      = false
      @sent         = false
      @content_type = nil
      @charset      = nil

      if content_type = self[CONTENT_TYPE]
        type, charset = content_type.split(/;\s*charset=/)
        @content_type = Mime::Type.lookup(type)
        @charset = charset || self.class.default_charset
      end

      prepare_cache_control!

      yield self if block_given?
    end

    def await_commit
      synchronize do
        @cv.wait_until { @committed }
      end
    end

    def await_sent
      synchronize { @cv.wait_until { @sent } }
    end

    def commit!
      synchronize do
        before_committed
        @committed = true
        @cv.broadcast
      end
    end

    def sending!
      synchronize do
        before_sending
        @sending = true
        @cv.broadcast
      end
    end

    def sent!
      synchronize do
        @sent = true
        @cv.broadcast
      end
    end

    def sending?;   synchronize { @sending };   end
    def committed?; synchronize { @committed }; end
    def sent?;      synchronize { @sent };      end

    # Sets the HTTP status code.
    def status=(status)
      @status = Rack::Utils.status_code(status)
    end

    # Sets the HTTP content type.
    def content_type=(content_type)
      @content_type = content_type.to_s
    end

    # The response code of the request.
    def response_code
      @status
    end

    # Returns a string to ensure compatibility with <tt>Net::HTTPResponse</tt>.
    def code
      @status.to_s
    end

    # Returns the corresponding message for the current HTTP status code:
    #
    #   response.status = 200
    #   response.message # => "OK"
    #
    #   response.status = 404
    #   response.message # => "Not Found"
    #
    def message
      Rack::Utils::HTTP_STATUS_CODES[@status]
    end
    alias_method :status_message, :message

    # Returns the content of the response as a string. This contains the contents
    # of any calls to <tt>render</tt>.
    def body
      strings = []
      each { |part| strings << part.to_s }
      strings.join
    end

    EMPTY = " "

    # Allows you to manually set or override the response body.
    def body=(body)
      @blank = true if body == EMPTY

      if body.respond_to?(:to_path)
        @stream = body
      else
        synchronize do
          @stream = build_buffer self, munge_body_object(body)
        end
      end
    end

    def body_parts
      parts = []
      @stream.each { |x| parts << x }
      parts
    end

    def set_cookie(key, value)
      ::Rack::Utils.set_cookie_header!(header, key, value)
    end

    def delete_cookie(key, value={})
      ::Rack::Utils.delete_cookie_header!(header, key, value)
    end

    # The location header we'll be responding with.
    def location
      headers[LOCATION]
    end
    alias_method :redirect_url, :location

    # Sets the location header we'll be responding with.
    def location=(url)
      headers[LOCATION] = url
    end

    def close
      stream.close if stream.respond_to?(:close)
    end

    def abort
      if stream.respond_to?(:abort)
        stream.abort
      elsif stream.respond_to?(:close)
        # `stream.close` should really be reserved for a close from the
        # other direction, but we must fall back to it for
        # compatibility.
        stream.close
      end
    end

    # Turns the Response into a Rack-compatible array of the status, headers,
    # and body. Allows explict splatting:
    #
    #   status, headers, body = *response
    def to_a
      rack_response @status, @header.to_hash
    end
    alias prepare! to_a

    # Be super clear that a response object is not an Array. Defining this
    # would make implicit splatting work, but it also makes adding responses
    # as arrays work, and "flattening" responses, cascading to the rack body!
    # Not sensible behavior.
    def to_ary
      ActiveSupport::Deprecation.warn(<<-MSG.squish)
        `ActionDispatch::Response#to_ary` no longer performs implicit conversion
        to an array. Please use `response.to_a` instead, or a splat like `status,
        headers, body = *response`.
      MSG

      to_a
    end

    # Returns the response cookies, converted to a Hash of (name => value) pairs
    #
    #   assert_equal 'AuthorOfNewPage', r.cookies['author']
    def cookies
      cookies = {}
      if header = self[SET_COOKIE]
        header = header.split("\n") if header.respond_to?(:to_str)
        header.each do |cookie|
          if pair = cookie.split(';').first
            key, value = pair.split("=").map { |v| Rack::Utils.unescape(v) }
            cookies[key] = value
          end
        end
      end
      cookies
    end

  private

    def before_committed
    end

    def before_sending
    end

    def merge_default_headers(original, default)
      return original unless default.respond_to?(:merge)

      default.merge(original)
    end

    def build_buffer(response, body)
      Buffer.new response, body
    end

    def munge_body_object(body)
      body.respond_to?(:each) ? body : [body]
    end

    def assign_default_content_type_and_charset!(headers)
      return if headers[CONTENT_TYPE].present?

      @content_type ||= Mime::HTML
      @charset      ||= self.class.default_charset unless @charset == false

      type = @content_type.to_s.dup
      type << "; charset=#{@charset}" if append_charset?

      headers[CONTENT_TYPE] = type
    end

    def append_charset?
      !@sending_file && @charset != false
    end

    class RackBody
      def initialize(response)
        @response = response
      end

      def each(*args, &block)
        @response.each(*args, &block)
      end

      def close
        # Rack "close" maps to Response#abort, and *not* Response#close
        # (which is used when the controller's finished writing)
        @response.abort
      end

      def body
        @response.body
      end

      def respond_to?(method, include_private = false)
        if method.to_s == 'to_path'
          @response.stream.respond_to?(method)
        else
          super
        end
      end

      def to_path
        @response.stream.to_path
      end

      def to_ary
        nil
      end
    end

    def rack_response(status, header)
      assign_default_content_type_and_charset!(header)
      handle_conditional_get!

      header[SET_COOKIE] = header[SET_COOKIE].join("\n") if header[SET_COOKIE].respond_to?(:join)

      if NO_CONTENT_CODES.include?(@status)
        header.delete CONTENT_TYPE
        [status, header, []]
      else
        [status, header, RackBody.new(self)]
      end
    end
  end
end
