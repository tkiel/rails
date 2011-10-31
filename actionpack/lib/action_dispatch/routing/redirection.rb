require 'action_dispatch/http/request'
require 'active_support/deprecation/reporting'

module ActionDispatch
  module Routing
    class Redirect
      attr_reader :status, :block

      def initialize(status, block)
        @status = status
        @block  = block
      end

      def call(env)
        req = Request.new(env)

        uri = URI.parse(path(req.symbolized_path_parameters, req))
        uri.scheme ||= req.scheme
        uri.host   ||= req.host
        uri.port   ||= req.port unless req.standard_port?

        body = %(<html><body>You are being <a href="#{ERB::Util.h(uri.to_s)}">redirected</a>.</body></html>)

        headers = {
          'Location' => uri.to_s,
          'Content-Type' => 'text/html',
          'Content-Length' => body.length.to_s
        }

        [ status, headers, [body] ]
      end

      def path(params, request)
        block.call params, request
      end
    end

    class OptionRedirect < Redirect
      alias :options :block

      def path(params, request)
        url_options = {
          :protocol => request.protocol,
          :host     => request.host,
          :port     => request.optional_port,
          :path     => request.path,
          :params   => request.query_parameters
        }.merge options

        ActionDispatch::Http::URL.url_for url_options
      end
    end

    module Redirection

      # Redirect any path to another path:
      #
      #   match "/stories" => redirect("/posts")
      #
      # You can also use interpolation in the supplied redirect argument:
      #
      #   match 'docs/:article', :to => redirect('/wiki/%{article}')
      #
      # Alternatively you can use one of the other syntaxes:
      #
      # The block version of redirect allows for the easy encapsulation of any logic associated with
      # the redirect in question. Either the params and request are supplied as arguments, or just
      # params, depending of how many arguments your block accepts. A string is required as a
      # return value.
      #
      #   match 'jokes/:number', :to => redirect do |params, request|
      #     path = (params[:number].to_i.even? ? "/wheres-the-beef" : "/i-love-lamp")
      #     "http://#{request.host_with_port}/#{path}"
      #   end
      #
      # The options version of redirect allows you to supply only the parts of the url which need
      # to change, it also supports interpolation of the path similar to the first example.
      #
      #   match 'stores/:name',       :to => redirect(:subdomain => 'stores', :path => '/%{name}')
      #   match 'stores/:name(*all)', :to => redirect(:subdomain => 'stores', :path => '/%{name}%{all}')
      #
      # Finally, an object which responds to call can be supplied to redirect, allowing you to reuse
      # common redirect routes. The call method must accept two arguments, params and request, and return
      # a string.
      #
      #   match 'accounts/:name' => redirect(SubdomainRedirector.new('api'))
      #
      def redirect(*args, &block)
        options = args.last.is_a?(Hash) ? args.pop : {}
        status  = options.delete(:status) || 301

        path = args.shift

        if path.is_a?(String)
          block_redirect status, lambda { |params, request|
            (params.empty? || !path.match(/%\{\w*\}/)) ? path : (path % params)
          }
        elsif options.any?
          OptionRedirect.new(status, options)
        elsif path.respond_to?(:call)
          block_redirect status, path
        elsif block
          if block.arity < 2
            msg = "redirect blocks with arity of #{block.arity} are deprecated. Your block must take 2 parameters: the environment, and a request object"
            ActiveSupport::Deprecation.warn msg
            block_redirect status, lambda { |params, _| block.call(params) }
          else
            block_redirect status, block
          end
        else
          raise ArgumentError, "redirection argument not supported"
        end
      end

      private
        def block_redirect(status, path_proc)
          Redirect.new status, path_proc
        end
    end
  end
end
