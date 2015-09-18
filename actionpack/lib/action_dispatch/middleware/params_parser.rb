require 'action_dispatch/http/request'

module ActionDispatch
  # ActionDispatch::ParamsParser works for all the requests having any Content-Length
  # (like POST). It takes raw data from the request and puts it through the parser
  # that is picked based on Content-Type header.
  #
  # In case of any error while parsing data ParamsParser::ParseError is raised.
  class ParamsParser
    # Raised when raw data from the request cannot be parsed by the parser
    # defined for request's content mime type.
    class ParseError < StandardError
      attr_reader :original_exception

      def initialize(message, original_exception)
        super(message)
        @original_exception = original_exception
      end
    end

    DEFAULT_PARSERS = {
      Mime::JSON => lambda { |raw_post|
        data = ActiveSupport::JSON.decode(raw_post)
        data.is_a?(Hash) ? data : {:_json => data}
      }
    }

    # Create a new +ParamsParser+ middleware instance.
    #
    # The +parsers+ argument can take Hash of parsers where key is identifying
    # content mime type, and value is a lambda that is going to process data.
    def initialize(app, parsers = {})
      @app, @parsers = app, DEFAULT_PARSERS.merge(parsers)
    end

    def call(env)
      request = Request.new(env)

      request.params_parsers = @parsers

      request.request_parameters

      @app.call(env)
    end
  end
end
