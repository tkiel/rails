module ActionController
  class RedirectBackError < AbstractController::Error #:nodoc:
    DEFAULT_MESSAGE = 'No HTTP_REFERER was set in the request to this action, so redirect_to :back could not be called successfully. If this is a test, make sure to specify request.env["HTTP_REFERER"].'

    def initialize(message = nil)
      super(message || DEFAULT_MESSAGE)
    end
  end

  module Redirecting
    extend ActiveSupport::Concern

    include AbstractController::Logger
    include ActionController::RackDelegation
    include ActionController::UrlFor

    # Redirects the browser to the target specified in +options+. This parameter can take one of three forms:
    #
    # * <tt>Hash</tt> - The URL will be generated by calling url_for with the +options+.
    # * <tt>Record</tt> - The URL will be generated by calling url_for with the +options+, which will reference a named URL for that record.
    # * <tt>String</tt> starting with <tt>protocol://</tt> (like <tt>http://</tt>) or a protocol relative reference (like <tt>//</tt>) - Is passed straight through as the target for redirection.
    # * <tt>String</tt> not containing a protocol - The current protocol and host is prepended to the string.
    # * <tt>Proc</tt> - A block that will be executed in the controller's context. Should return any option accepted by +redirect_to+.
    # * <tt>:back</tt> - Back to the page that issued the request. Useful for forms that are triggered from multiple places.
    #   Short-hand for <tt>redirect_to(request.env["HTTP_REFERER"])</tt>
    #
    # Examples:
    #   redirect_to :action => "show", :id => 5
    #   redirect_to post
    #   redirect_to "http://www.rubyonrails.org"
    #   redirect_to "/images/screenshot.jpg"
    #   redirect_to articles_url
    #   redirect_to :back
    #   redirect_to proc { edit_post_url(@post) }
    #
    # The redirection happens as a "302 Moved" header unless otherwise specified.
    #
    # Examples:
    #   redirect_to post_url(@post), :status => :found
    #   redirect_to :action=>'atom', :status => :moved_permanently
    #   redirect_to post_url(@post), :status => 301
    #   redirect_to :action=>'atom', :status => 302
    #
    # The status code can either be a standard {HTTP Status code}[http://www.iana.org/assignments/http-status-codes] as an
    # integer, or a symbol representing the downcased, underscored and symbolized description.
    # Note that the status code must be a 3xx HTTP code, or redirection will not occur.
    #
    # It is also possible to assign a flash message as part of the redirection. There are two special accessors for the commonly used flash names
    # +alert+ and +notice+ as well as a general purpose +flash+ bucket.
    #
    # Examples:
    #   redirect_to post_url(@post), :alert => "Watch it, mister!"
    #   redirect_to post_url(@post), :status=> :found, :notice => "Pay attention to the road"
    #   redirect_to post_url(@post), :status => 301, :flash => { :updated_post_id => @post.id }
    #   redirect_to { :action=>'atom' }, :alert => "Something serious happened"
    #
    # When using <tt>redirect_to :back</tt>, if there is no referrer, ActionController::RedirectBackError will be raised. You may specify some fallback
    # behavior for this case by rescuing ActionController::RedirectBackError.
    def redirect_to(options = {}, response_status = {}) #:doc:
      raise ActionControllerError.new("Cannot redirect to nil!") unless options
      raise AbstractController::DoubleRenderError if response_body

      self.status        = _extract_redirect_to_status(options, response_status)
      self.location      = _compute_redirect_to_location(options)
      self.response_body = "<html><body>You are being <a href=\"#{ERB::Util.h(location)}\">redirected</a>.</body></html>"
    end

    private
      def _extract_redirect_to_status(options, response_status)
        status = if options.is_a?(Hash) && options.key?(:status)
          Rack::Utils.status_code(options.delete(:status))
        elsif response_status.key?(:status)
          Rack::Utils.status_code(response_status[:status])
        else
          302
        end
      end

      def _compute_redirect_to_location(options)
        case options
        # The scheme name consist of a letter followed by any combination of
        # letters, digits, and the plus ("+"), period ("."), or hyphen ("-")
        # characters; and is terminated by a colon (":").
        # The protocol relative scheme starts with a double slash "//"
        when %r{^(\w[\w+.-]*:|//).*}
          options
        when String
          request.protocol + request.host_with_port + options
        when :back
          raise RedirectBackError unless refer = request.headers["Referer"]
          refer
        when Proc
          _compute_redirect_to_location options.call
        else
          url_for(options)
        end.delete("\0\r\n")
      end
  end
end
