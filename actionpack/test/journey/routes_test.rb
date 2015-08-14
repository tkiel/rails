require 'abstract_unit'

module ActionDispatch
  module Journey
    class TestRoutes < ActiveSupport::TestCase
      attr_reader :routes

      def setup
        @routes = Routes.new
        super
      end

      MyMapping = Struct.new(:application, :path, :conditions, :required_defaults, :defaults)

      def add_route(app, path, conditions, required_defaults, defaults, name = nil)
        @routes.add_route(name, MyMapping.new(app, path, conditions, required_defaults, defaults))
      end

      def test_clear
        path    = Path::Pattern.build '/foo(/:id)', {}, ['/.?'], true
        requirements = { :hello => /world/ }

        add_route nil, path, requirements, [], {:id => nil}, {}
        assert_not routes.empty?
        assert_equal 1, routes.length

        routes.clear
        assert routes.empty?
        assert_equal 0, routes.length
      end

      def test_ast
        path   = Path::Pattern.from_string '/hello'

        add_route nil, path, {}, [], {}, {}
        ast = routes.ast
        add_route nil, path, {}, [], {}, {}
        assert_not_equal ast, routes.ast
      end

      def test_simulator_changes
        path   = Path::Pattern.from_string '/hello'

        add_route nil, path, {}, [], {}, {}
        sim = routes.simulator
        add_route nil, path, {}, [], {}, {}
        assert_not_equal sim, routes.simulator
      end

      def test_partition_route
        path   = Path::Pattern.from_string '/hello'

        anchored_route = add_route nil, path, {}, [], {}, {}
        assert_equal [anchored_route], @routes.anchored_routes
        assert_equal [], @routes.custom_routes

        path = Path::Pattern.build(
          "/hello/:who", { who: /\d/ }, ['/', '.', '?'], false
        )

        custom_route = add_route nil, path, {}, [], {}, {}
        assert_equal [custom_route], @routes.custom_routes
        assert_equal [anchored_route], @routes.anchored_routes
      end

      def test_first_name_wins
        one   = Path::Pattern.from_string '/hello'
        two   = Path::Pattern.from_string '/aaron'

        add_route nil, one, {}, [], {}, 'aaron'
        add_route nil, two, {}, [], {}, 'aaron'

        assert_equal '/hello', routes.named_routes['aaron'].path.spec.to_s
      end
    end
  end
end
