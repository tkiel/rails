# frozen_string_literal: true

module ActionController
  module Redirecting
    extend ActiveSupport::Concern

    include AbstractController::Logger
    include ActionController::UrlFor

    # Redirects the browser to the target specified in +options+. This parameter can be any one of:
    #
    # * <tt>Hash</tt> - The URL will be generated by calling url_for with the +options+.
    # * <tt>Record</tt> - The URL will be generated by calling url_for with the +options+, which will reference a named URL for that record.
    # * <tt>String</tt> starting with <tt>protocol://</tt> (like <tt>http://</tt>) or a protocol relative reference (like <tt>//</tt>) - Is passed straight through as the target for redirection.
    # * <tt>String</tt> not containing a protocol - The current protocol and host is prepended to the string.
    # * <tt>Proc</tt> - A block that will be executed in the controller's context. Should return any option accepted by +redirect_to+.
    #
    # === Examples:
    #
    #   redirect_to action: "show", id: 5
    #   redirect_to @post
    #   redirect_to "http://www.rubyonrails.org"
    #   redirect_to "/images/screenshot.jpg"
    #   redirect_to posts_url
    #   redirect_to proc { edit_post_url(@post) }
    #
    # The redirection happens as a <tt>302 Found</tt> header unless otherwise specified using the <tt>:status</tt> option:
    #
    #   redirect_to post_url(@post), status: :found
    #   redirect_to action: 'atom', status: :moved_permanently
    #   redirect_to post_url(@post), status: 301
    #   redirect_to action: 'atom', status: 302
    #
    # The status code can either be a standard {HTTP Status code}[https://www.iana.org/assignments/http-status-codes] as an
    # integer, or a symbol representing the downcased, underscored and symbolized description.
    # Note that the status code must be a 3xx HTTP code, or redirection will not occur.
    #
    # If you are using XHR requests other than GET or POST and redirecting after the
    # request then some browsers will follow the redirect using the original request
    # method. This may lead to undesirable behavior such as a double DELETE. To work
    # around this you can return a <tt>303 See Other</tt> status code which will be
    # followed using a GET request.
    #
    #   redirect_to posts_url, status: :see_other
    #   redirect_to action: 'index', status: 303
    #
    # It is also possible to assign a flash message as part of the redirection. There are two special accessors for the commonly used flash names
    # +alert+ and +notice+ as well as a general purpose +flash+ bucket.
    #
    #   redirect_to post_url(@post), alert: "Watch it, mister!"
    #   redirect_to post_url(@post), status: :found, notice: "Pay attention to the road"
    #   redirect_to post_url(@post), status: 301, flash: { updated_post_id: @post.id }
    #   redirect_to({ action: 'atom' }, alert: "Something serious happened")
    #
    # Statements after +redirect_to+ in our controller get executed, so +redirect_to+ doesn't stop the execution of the function.
    # To terminate the execution of the function immediately after the +redirect_to+, use return.
    #   redirect_to post_url(@post) and return
    def redirect_to(options = {}, response_status = {})
      raise ActionControllerError.new("Cannot redirect to nil!") unless options
      raise AbstractController::DoubleRenderError if response_body

      self.status        = _extract_redirect_to_status(options, response_status)
      self.location      = _compute_redirect_to_location(request, options)
      self.response_body = "<html><body>You are being <a href=\"#{ERB::Util.unwrapped_html_escape(response.location)}\">redirected</a>.</body></html>"
    end

    # Redirects the browser to the page that issued the request (the referrer)
    # if possible, otherwise redirects to the provided default fallback
    # location.
    #
    # The referrer information is pulled from the HTTP +Referer+ (sic) header on
    # the request. This is an optional header and its presence on the request is
    # subject to browser security settings and user preferences. If the request
    # is missing this header, the <tt>fallback_location</tt> will be used.
    #
    #   redirect_back fallback_location: { action: "show", id: 5 }
    #   redirect_back fallback_location: @post
    #   redirect_back fallback_location: "http://www.rubyonrails.org"
    #   redirect_back fallback_location: "/images/screenshot.jpg"
    #   redirect_back fallback_location: posts_url
    #   redirect_back fallback_location: proc { edit_post_url(@post) }
    #   redirect_back fallback_location: '/', allow_other_host: false
    #
    # ==== Options
    # * <tt>:fallback_location</tt> - The default fallback location that will be used on missing +Referer+ header.
    # * <tt>:allow_other_host</tt> - Allow or disallow redirection to the host that is different to the current host, defaults to true.
    #
    # All other options that can be passed to <tt>redirect_to</tt> are accepted as
    # options and the behavior is identical.
    def redirect_back(fallback_location:, allow_other_host: true, **args)
      referer = request.headers["Referer"]
      redirect_to_referer = referer && (allow_other_host || _url_host_allowed?(referer))
      redirect_to redirect_to_referer ? referer : fallback_location, **args
    end

    def _compute_redirect_to_location(request, options) #:nodoc:
      case options
      # The scheme name consist of a letter followed by any combination of
      # letters, digits, and the plus ("+"), period ("."), or hyphen ("-")
      # characters; and is terminated by a colon (":").
      # See https://tools.ietf.org/html/rfc3986#section-3.1
      # The protocol relative scheme starts with a double slash "//".
      when /\A([a-z][a-z\d\-+\.]*:|\/\/).*/i
        options
      when String
        request.protocol + request.host_with_port + options
      when Proc
        _compute_redirect_to_location request, options.call
      else
        url_for(options)
      end.delete("\0\r\n")
    end
    module_function :_compute_redirect_to_location
    public :_compute_redirect_to_location

    private
      def _extract_redirect_to_status(options, response_status)
        if options.is_a?(Hash) && options.key?(:status)
          Rack::Utils.status_code(options.delete(:status))
        elsif response_status.key?(:status)
          Rack::Utils.status_code(response_status[:status])
        else
          302
        end
      end

      def _url_host_allowed?(url)
        URI(url.to_s).host == request.host
      rescue ArgumentError, URI::Error
        false
      end
  end
end
