require 'securerandom'
require 'active_support/core_ext/string/access'

module ActionDispatch
  # Makes a unique request id available to the action_dispatch.request_id env variable (which is then accessible through
  # ActionDispatch::Request#uuid or the alias ActionDispatch::Request#request_id) and sends the same id to the client via the X-Request-Id header.
  #
  # The unique request id is either based on the X-Request-Id header in the request, which would typically be generated
  # by a firewall, load balancer, or the web server, or, if this header is not available, a random uuid. If the
  # header is accepted from the outside world, we sanitize it to a max of 255 chars and alphanumeric and dashes only.
  #
  # The unique request id can be used to trace a request end-to-end and would typically end up being part of log files
  # from multiple pieces of the stack.
  class RequestId
    X_REQUEST_ID = "X-Request-Id".freeze # :nodoc:
    ACTION_DISPATCH_REQUEST_ID = "action_dispatch.request_id".freeze # :nodoc:
    HTTP_X_REQUEST_ID = "HTTP_X_REQUEST_ID".freeze # :nodoc:

    def initialize(app)
      @app = app
    end

    def call(env)
      env[ACTION_DISPATCH_REQUEST_ID] = external_request_id(env) || internal_request_id
      @app.call(env).tap { |_status, headers, _body| headers[X_REQUEST_ID] = env[ACTION_DISPATCH_REQUEST_ID] }
    end

    private
      def external_request_id(env)
        if request_id = env[HTTP_X_REQUEST_ID].presence
          request_id.gsub(/[^\w\-]/, "".freeze).first(255)
        end
      end

      def internal_request_id
        SecureRandom.uuid
      end
  end
end
