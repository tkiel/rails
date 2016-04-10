require 'action_dispatch/journey'
require 'active_support/concern'
require 'active_support/core_ext/object/to_query'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/module/remove_method'
require 'active_support/core_ext/array/extract_options'
require 'action_controller/metal/exceptions'
require 'action_dispatch/http/request'
require 'action_dispatch/routing/endpoint'

module ActionDispatch
  module Routing
    # :stopdoc:
    class RouteSet
      # Since the router holds references to many parts of the system
      # like engines, controllers and the application itself, inspecting
      # the route set can actually be really slow, therefore we default
      # alias inspect to to_s.
      alias inspect to_s

      class Dispatcher < Routing::Endpoint
        def initialize(raise_on_name_error)
          @raise_on_name_error = raise_on_name_error
        end

        def dispatcher?; true; end

        def serve(req)
          params     = req.path_parameters
          controller = controller req
          res        = controller.make_response! req
          dispatch(controller, params[:action], req, res)
        rescue ActionController::RoutingError
          if @raise_on_name_error
            raise
          else
            return [404, {'X-Cascade' => 'pass'}, []]
          end
        end

      private

        def controller(req)
          req.controller_class
        rescue NameError => e
          raise ActionController::RoutingError, e.message, e.backtrace
        end

        def dispatch(controller, action, req, res)
          controller.dispatch(action, req, res)
        end
      end

      class StaticDispatcher < Dispatcher
        def initialize(controller_class)
          super(false)
          @controller_class = controller_class
        end

        private

        def controller(_); @controller_class; end
      end

      # A NamedRouteCollection instance is a collection of named routes, and also
      # maintains an anonymous module that can be used to install helpers for the
      # named routes.
      class NamedRouteCollection
        include Enumerable
        attr_reader :routes, :url_helpers_module, :path_helpers_module
        private :routes

        def initialize
          @routes  = {}
          @path_helpers = Set.new
          @url_helpers = Set.new
          @url_helpers_module  = Module.new
          @path_helpers_module = Module.new
        end

        def route_defined?(name)
          key = name.to_sym
          @path_helpers.include?(key) || @url_helpers.include?(key)
        end

        def helper_names
          @path_helpers.map(&:to_s) + @url_helpers.map(&:to_s)
        end

        def clear!
          @path_helpers.each do |helper|
            @path_helpers_module.send :undef_method, helper
          end

          @url_helpers.each do |helper|
            @url_helpers_module.send  :undef_method, helper
          end

          @routes.clear
          @path_helpers.clear
          @url_helpers.clear
        end

        def add(name, route)
          key       = name.to_sym
          path_name = :"#{name}_path"
          url_name  = :"#{name}_url"

          if routes.key? key
            @path_helpers_module.send :undef_method, path_name
            @url_helpers_module.send  :undef_method, url_name
          end
          routes[key] = route
          define_url_helper @path_helpers_module, route, path_name, route.defaults, name, PATH
          define_url_helper @url_helpers_module,  route, url_name,  route.defaults, name, UNKNOWN

          @path_helpers << path_name
          @url_helpers << url_name
        end

        def get(name)
          routes[name.to_sym]
        end

        def key?(name)
          return unless name
          routes.key? name.to_sym
        end

        alias []=   add
        alias []    get
        alias clear clear!

        def each
          routes.each { |name, route| yield name, route }
          self
        end

        def names
          routes.keys
        end

        def length
          routes.length
        end

        class UrlHelper
          def self.create(route, options, route_name, url_strategy)
            if optimize_helper?(route)
              OptimizedUrlHelper.new(route, options, route_name, url_strategy)
            else
              new route, options, route_name, url_strategy
            end
          end

          def self.optimize_helper?(route)
            !route.glob? && route.path.requirements.empty?
          end

          attr_reader :url_strategy, :route_name

          class OptimizedUrlHelper < UrlHelper
            attr_reader :arg_size

            def initialize(route, options, route_name, url_strategy)
              super
              @required_parts = @route.required_parts
              @arg_size       = @required_parts.size
            end

            def call(t, args, inner_options)
              if args.size == arg_size && !inner_options && optimize_routes_generation?(t)
                options = t.url_options.merge @options
                options[:path] = optimized_helper(args)
                url_strategy.call options
              else
                super
              end
            end

            private

            def optimized_helper(args)
              params = parameterize_args(args) do
                raise_generation_error(args)
              end

              @route.format params
            end

            def optimize_routes_generation?(t)
              t.send(:optimize_routes_generation?)
            end

            def parameterize_args(args)
              params = {}
              @arg_size.times { |i|
                key = @required_parts[i]
                value = args[i].to_param
                yield key if value.nil? || value.empty?
                params[key] = value
              }
              params
            end

            def raise_generation_error(args)
              missing_keys = []
              params = parameterize_args(args) { |missing_key|
                missing_keys << missing_key
              }
              constraints = Hash[@route.requirements.merge(params).sort_by{|k,v| k.to_s}]
              message = "No route matches #{constraints.inspect}"
              message << " missing required keys: #{missing_keys.sort.inspect}"

              raise ActionController::UrlGenerationError, message
            end
          end

          def initialize(route, options, route_name, url_strategy)
            @options      = options
            @segment_keys = route.segment_keys.uniq
            @route        = route
            @url_strategy = url_strategy
            @route_name   = route_name
          end

          def call(t, args, inner_options)
            controller_options = t.url_options
            options = controller_options.merge @options
            hash = handle_positional_args(controller_options,
                                          inner_options || {},
                                          args,
                                          options,
                                          @segment_keys)

            t._routes.url_for(hash, route_name, url_strategy)
          end

          def handle_positional_args(controller_options, inner_options, args, result, path_params)
            if args.size > 0
              # take format into account
              if path_params.include?(:format)
                path_params_size = path_params.size - 1
              else
                path_params_size = path_params.size
              end

              if args.size < path_params_size
                path_params -= controller_options.keys
                path_params -= result.keys
              end
              inner_options.each_key do |key|
                path_params.delete(key)
              end

              args.each_with_index do |arg, index|
                param = path_params[index]
                result[param] = arg if param
              end
            end

            result.merge!(inner_options)
          end
        end

        private
        # Create a url helper allowing ordered parameters to be associated
        # with corresponding dynamic segments, so you can do:
        #
        #   foo_url(bar, baz, bang)
        #
        # Instead of:
        #
        #   foo_url(bar: bar, baz: baz, bang: bang)
        #
        # Also allow options hash, so you can do:
        #
        #   foo_url(bar, baz, bang, sort_by: 'baz')
        #
        def define_url_helper(mod, route, name, opts, route_key, url_strategy)
          helper = UrlHelper.create(route, opts, route_key, url_strategy)
          mod.module_eval do
            define_method(name) do |*args|
              last = args.last
              options = case last
                        when Hash
                          args.pop
                        when ActionController::Parameters
                          if last.permitted?
                            args.pop.to_h
                          else
                            raise ArgumentError, "Generating a URL from non sanitized request parameters is insecure!"
                          end
                        end
              helper.call self, args, options
            end
          end
        end
      end

      # strategy for building urls to send to the client
      PATH    = ->(options) { ActionDispatch::Http::URL.path_for(options) }
      UNKNOWN = ->(options) { ActionDispatch::Http::URL.url_for(options) }

      attr_accessor :formatter, :set, :named_routes, :default_scope, :router
      attr_accessor :disable_clear_and_finalize, :resources_path_names
      attr_accessor :default_url_options
      attr_reader :env_key

      alias :routes :set

      def self.default_resources_path_names
        { :new => 'new', :edit => 'edit' }
      end

      def self.new_with_config(config)
        route_set_config = DEFAULT_CONFIG

        # engines apparently don't have this set
        if config.respond_to? :relative_url_root
          route_set_config.relative_url_root = config.relative_url_root
        end

        if config.respond_to? :api_only
          route_set_config.api_only = config.api_only
        end

        new route_set_config
      end

      Config = Struct.new :relative_url_root, :api_only

      DEFAULT_CONFIG = Config.new(nil, false)

      def initialize(config = DEFAULT_CONFIG)
        self.named_routes = NamedRouteCollection.new
        self.resources_path_names = self.class.default_resources_path_names
        self.default_url_options = {}

        @config                     = config
        @append                     = []
        @prepend                    = []
        @disable_clear_and_finalize = false
        @finalized                  = false
        @env_key                    = "ROUTES_#{object_id}_SCRIPT_NAME".freeze

        @set    = Journey::Routes.new
        @router = Journey::Router.new @set
        @formatter = Journey::Formatter.new self
      end

      def relative_url_root
        @config.relative_url_root
      end

      def api_only?
        @config.api_only
      end

      def request_class
        ActionDispatch::Request
      end

      def make_request(env)
        request_class.new env
      end
      private :make_request

      def draw(&block)
        clear! unless @disable_clear_and_finalize
        eval_block(block)
        finalize! unless @disable_clear_and_finalize
        nil
      end

      def append(&block)
        @append << block
      end

      def prepend(&block)
        @prepend << block
      end

      def eval_block(block)
        mapper = Mapper.new(self)
        if default_scope
          mapper.with_default_scope(default_scope, &block)
        else
          mapper.instance_exec(&block)
        end
      end
      private :eval_block

      def finalize!
        return if @finalized
        @append.each { |blk| eval_block(blk) }
        @finalized = true
      end

      def clear!
        @finalized = false
        named_routes.clear
        set.clear
        formatter.clear
        @prepend.each { |blk| eval_block(blk) }
      end

      module MountedHelpers
        extend ActiveSupport::Concern
        include UrlFor
      end

      # Contains all the mounted helpers across different
      # engines and the `main_app` helper for the application.
      # You can include this in your classes if you want to
      # access routes for other engines.
      def mounted_helpers
        MountedHelpers
      end

      def define_mounted_helper(name)
        return if MountedHelpers.method_defined?(name)

        routes = self
        helpers = routes.url_helpers

        MountedHelpers.class_eval do
          define_method "_#{name}" do
            RoutesProxy.new(routes, _routes_context, helpers)
          end
        end

        MountedHelpers.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
          def #{name}
            @_#{name} ||= _#{name}
          end
        RUBY
      end

      def url_helpers(supports_path = true)
        routes = self

        Module.new do
          extend ActiveSupport::Concern
          include UrlFor

          # Define url_for in the singleton level so one can do:
          # Rails.application.routes.url_helpers.url_for(args)
          @_routes = routes
          class << self
            def url_for(options)
              @_routes.url_for(options)
            end

            def optimize_routes_generation?
              @_routes.optimize_routes_generation?
            end

            attr_reader :_routes
            def url_options; {}; end
          end

          url_helpers = routes.named_routes.url_helpers_module

          # Make named_routes available in the module singleton
          # as well, so one can do:
          # Rails.application.routes.url_helpers.posts_path
          extend url_helpers

          # Any class that includes this module will get all
          # named routes...
          include url_helpers

          if supports_path
            path_helpers = routes.named_routes.path_helpers_module

            include path_helpers
            extend path_helpers
          end

          # plus a singleton class method called _routes ...
          included do
            singleton_class.send(:redefine_method, :_routes) { routes }
          end

          # And an instance method _routes. Note that
          # UrlFor (included in this module) add extra
          # conveniences for working with @_routes.
          define_method(:_routes) { @_routes || routes }

          define_method(:_generate_paths_by_default) do
            supports_path
          end

          private :_generate_paths_by_default
        end
      end

      def empty?
        routes.empty?
      end

      def add_route(mapping, path_ast, name, anchor)
        raise ArgumentError, "Invalid route name: '#{name}'" unless name.blank? || name.to_s.match(/^[_a-z]\w*$/i)

        if name && named_routes[name]
          raise ArgumentError, "Invalid route name, already in use: '#{name}' \n" \
            "You may have defined two routes with the same name using the `:as` option, or " \
            "you may be overriding a route already defined by a resource with the same naming. " \
            "For the latter, you can restrict the routes created with `resources` as explained here: \n" \
            "http://guides.rubyonrails.org/routing.html#restricting-the-routes-created"
        end

        route = @set.add_route(name, mapping)
        named_routes[name] = route if name

        if route.segment_keys.include?(:controller)
          ActiveSupport::Deprecation.warn(<<-MSG.squish)
            Using a dynamic :controller segment in a route is deprecated and
            will be removed in Rails 5.1.
          MSG
        end

        if route.segment_keys.include?(:action)
          ActiveSupport::Deprecation.warn(<<-MSG.squish)
            Using a dynamic :action segment in a route is deprecated and
            will be removed in Rails 5.1.
          MSG
        end

        route
      end

      class Generator
        PARAMETERIZE = lambda do |name, value|
          if name == :controller
            value
          else
            value.to_param
          end
        end

        attr_reader :options, :recall, :set, :named_route

        def initialize(named_route, options, recall, set)
          @named_route = named_route
          @options     = options
          @recall      = recall
          @set         = set

          normalize_recall!
          normalize_options!
          normalize_controller_action_id!
          use_relative_controller!
          normalize_controller!
          normalize_action!
        end

        def controller
          @options[:controller]
        end

        def current_controller
          @recall[:controller]
        end

        def use_recall_for(key)
          if @recall[key] && (!@options.key?(key) || @options[key] == @recall[key])
            if !named_route_exists? || segment_keys.include?(key)
              @options[key] = @recall[key]
            end
          end
        end

        # Set 'index' as default action for recall
        def normalize_recall!
          @recall[:action] ||= 'index'
        end

        def normalize_options!
          # If an explicit :controller was given, always make :action explicit
          # too, so that action expiry works as expected for things like
          #
          #   generate({controller: 'content'}, {controller: 'content', action: 'show'})
          #
          # (the above is from the unit tests). In the above case, because the
          # controller was explicitly given, but no action, the action is implied to
          # be "index", not the recalled action of "show".

          if options[:controller]
            options[:action]     ||= 'index'
            options[:controller]   = options[:controller].to_s
          end

          if options.key?(:action)
            options[:action] = (options[:action] || 'index').to_s
          end
        end

        # This pulls :controller, :action, and :id out of the recall.
        # The recall key is only used if there is no key in the options
        # or if the key in the options is identical. If any of
        # :controller, :action or :id is not found, don't pull any
        # more keys from the recall.
        def normalize_controller_action_id!
          use_recall_for(:controller) or return
          use_recall_for(:action) or return
          use_recall_for(:id)
        end

        # if the current controller is "foo/bar/baz" and controller: "baz/bat"
        # is specified, the controller becomes "foo/baz/bat"
        def use_relative_controller!
          if !named_route && different_controller? && !controller.start_with?("/")
            old_parts = current_controller.split('/')
            size = controller.count("/") + 1
            parts = old_parts[0...-size] << controller
            @options[:controller] = parts.join("/")
          end
        end

        # Remove leading slashes from controllers
        def normalize_controller!
          if controller
            if controller.start_with?("/".freeze)
              @options[:controller] = controller[1..-1]
            else
              @options[:controller] = controller
            end
          end
        end

        # Move 'index' action from options to recall
        def normalize_action!
          if @options[:action] == 'index'.freeze
            @recall[:action] = @options.delete(:action)
          end
        end

        # Generates a path from routes, returns [path, params].
        # If no route is generated the formatter will raise ActionController::UrlGenerationError
        def generate
          @set.formatter.generate(named_route, options, recall, PARAMETERIZE)
        end

        def different_controller?
          return false unless current_controller
          controller.to_param != current_controller.to_param
        end

        private
          def named_route_exists?
            named_route && set.named_routes[named_route]
          end

          def segment_keys
            set.named_routes[named_route].segment_keys
          end
      end

      # Generate the path indicated by the arguments, and return an array of
      # the keys that were not used to generate it.
      def extra_keys(options, recall={})
        generate_extras(options, recall).last
      end

      def generate_extras(options, recall={})
        route_key = options.delete :use_route
        path, params = generate(route_key, options, recall)
        return path, params.keys
      end

      def generate(route_key, options, recall = {})
        Generator.new(route_key, options, recall, self).generate
      end
      private :generate

      RESERVED_OPTIONS = [:host, :protocol, :port, :subdomain, :domain, :tld_length,
                          :trailing_slash, :anchor, :params, :only_path, :script_name,
                          :original_script_name, :relative_url_root]

      def optimize_routes_generation?
        default_url_options.empty?
      end

      def find_script_name(options)
        options.delete(:script_name) || find_relative_url_root(options) || ''
      end

      def find_relative_url_root(options)
        options.delete(:relative_url_root) || relative_url_root
      end

      def path_for(options, route_name = nil)
        url_for(options, route_name, PATH)
      end

      # The +options+ argument must be a hash whose keys are *symbols*.
      def url_for(options, route_name = nil, url_strategy = UNKNOWN)
        options = default_url_options.merge options

        user = password = nil

        if options[:user] && options[:password]
          user     = options.delete :user
          password = options.delete :password
        end

        recall  = options.delete(:_recall) { {} }

        original_script_name = options.delete(:original_script_name)
        script_name = find_script_name options

        if original_script_name
          script_name = original_script_name + script_name
        end

        path_options = options.dup
        RESERVED_OPTIONS.each { |ro| path_options.delete ro }

        path, params = generate(route_name, path_options, recall)

        if options.key? :params
          params.merge! options[:params]
        end

        options[:path]        = path
        options[:script_name] = script_name
        options[:params]      = params
        options[:user]        = user
        options[:password]    = password

        url_strategy.call options
      end

      def call(env)
        req = make_request(env)
        req.path_info = Journey::Router::Utils.normalize_path(req.path_info)
        @router.serve(req)
      end

      def recognize_path(path, environment = {})
        method = (environment[:method] || "GET").to_s.upcase
        path = Journey::Router::Utils.normalize_path(path) unless path =~ %r{://}
        extras = environment[:extras] || {}

        begin
          env = Rack::MockRequest.env_for(path, {:method => method})
        rescue URI::InvalidURIError => e
          raise ActionController::RoutingError, e.message
        end

        req = make_request(env)
        @router.recognize(req) do |route, params|
          params.merge!(extras)
          params.each do |key, value|
            if value.is_a?(String)
              value = value.dup.force_encoding(Encoding::BINARY)
              params[key] = URI.parser.unescape(value)
            end
          end
          old_params = req.path_parameters
          req.path_parameters = old_params.merge params
          app = route.app
          if app.matches?(req) && app.dispatcher?
            begin
              req.controller_class
            rescue NameError
              raise ActionController::RoutingError, "A route matches #{path.inspect}, but references missing controller: #{params[:controller].camelize}Controller"
            end

            return req.path_parameters
          end
        end

        raise ActionController::RoutingError, "No route matches #{path.inspect}"
      end
    end
    # :startdoc:
  end
end
