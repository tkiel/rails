require 'active_support/core_ext/hash/indifferent_access'
require 'rack/utils'

module ActionDispatch
  class TestRequest < Request
    DEFAULT_ENV = Rack::MockRequest.env_for('/',
      'HTTP_HOST'                => 'test.host',
      'REMOTE_ADDR'              => '0.0.0.0',
      'HTTP_USER_AGENT'          => 'Rails Testing',
      "rack.request.cookie_hash" => {}.with_indifferent_access
    )

    # Create a new test request with default `env` values
    def self.create(env = {})
      env = Rails.application.env_config.merge(env) if defined?(Rails.application) && Rails.application
      new(default_env.merge(env))
    end

    def self.default_env
      DEFAULT_ENV
    end
    private_class_method :default_env

    def request_method=(method)
      @env['REQUEST_METHOD'] = method.to_s.upcase
    end

    def host=(host)
      @env['HTTP_HOST'] = host
    end

    def port=(number)
      @env['SERVER_PORT'] = number.to_i
    end

    def request_uri=(uri)
      @env['REQUEST_URI'] = uri
    end

    def path=(path)
      @env['PATH_INFO'] = path
    end

    def action=(action_name)
      path_parameters[:action] = action_name.to_s
    end

    def if_modified_since=(last_modified)
      @env['HTTP_IF_MODIFIED_SINCE'] = last_modified
    end

    def if_none_match=(etag)
      @env['HTTP_IF_NONE_MATCH'] = etag
    end

    def remote_addr=(addr)
      @env['REMOTE_ADDR'] = addr
    end

    def user_agent=(user_agent)
      @env['HTTP_USER_AGENT'] = user_agent
    end

    def accept=(mime_types)
      @env.delete('action_dispatch.request.accepts')
      @env['HTTP_ACCEPT'] = Array(mime_types).collect(&:to_s).join(",")
    end
  end
end
