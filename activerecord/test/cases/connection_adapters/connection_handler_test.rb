require "cases/helper"

module ActiveRecord
  module ConnectionAdapters

    class MergeAndResolveDefaultUrlConfigTest < ActiveRecord::TestCase

      def klass
        ActiveRecord::ConnectionHandling::MergeAndResolveDefaultUrlConfig
      end

      def setup
        @previous_database_url = ENV.delete("DATABASE_URL")
      end

      def teardown
        ENV["DATABASE_URL"] = @previous_database_url
      end

      def test_string_connection
        config   = { "production" => "postgres://localhost/foo" }
        actual   = klass.new(config).resolve
        expected = { "production" =>
                     { "adapter"  => "postgresql",
                       "database" => "foo",
                       "host"     => "localhost"
                      }
                    }
        assert_equal expected, actual
      end

      def test_url_sub_key
        config   = { "production" => { "url" => "postgres://localhost/foo" } }
        actual   = klass.new(config).resolve
        expected = { "production" =>
                     { "adapter"  => "postgresql",
                       "database" => "foo",
                       "host"     => "localhost"
                      }
                    }
        assert_equal expected, actual
      end

      def test_hash
        config = { "production" => { "adapter" => "postgres", "database" => "foo" } }
        actual = klass.new(config).resolve
        assert_equal config, actual
      end

      def test_blank
        config = {}
        actual = klass.new(config).resolve
        assert_equal config, actual
      end

      def test_blank_with_database_url
        ENV['DATABASE_URL'] = "postgres://localhost/foo"

        config   = {}
        actual   = klass.new(config).resolve
        expected = { "adapter"  => "postgresql",
                     "database" => "foo",
                     "host"     => "localhost" }
        assert_equal expected, actual["production"]
        assert_equal expected, actual["development"]
        assert_equal expected, actual["test"]
        assert_equal nil,      actual[:production]
        assert_equal nil,      actual[:development]
        assert_equal nil,      actual[:test]
      end

      def test_sting_with_database_url
        ENV['DATABASE_URL'] = "NOT-POSTGRES://localhost/NOT_FOO"

        config   = { "production" => "postgres://localhost/foo" }
        actual   = klass.new(config).resolve

        expected = { "production" =>
                     { "adapter"  => "postgresql",
                       "database" => "foo",
                       "host"     => "localhost"
                      }
                    }
        assert_equal expected, actual
      end

      def test_url_sub_key_with_database_url
        ENV['DATABASE_URL'] = "NOT-POSTGRES://localhost/NOT_FOO"

        config   = { "production" => { "url" => "postgres://localhost/foo" } }
        actual   = klass.new(config).resolve
        expected = { "production" =>
                    { "adapter"  => "postgresql",
                       "database" => "foo",
                       "host"     => "localhost"
                      }
                    }
        assert_equal expected, actual
      end

      def test_merge_no_conflicts_with_database_url
        ENV['DATABASE_URL'] = "postgres://localhost/foo"

        config   = {"production" => { "pool" => "5" } }
        actual   = klass.new(config).resolve
        expected = { "production" =>
                     { "adapter"  => "postgresql",
                       "database" => "foo",
                       "host"     => "localhost",
                       "pool"     => "5"
                      }
                    }
        assert_equal expected, actual
      end

      def test_merge_conflicts_with_database_url
        ENV['DATABASE_URL'] = "postgres://localhost/foo"

        config   = {"production" => { "adapter" => "NOT-POSTGRES", "database" => "NOT-FOO", "pool" => "5" } }
        actual   = klass.new(config).resolve
        expected = { "production" =>
                     { "adapter"  => "postgresql",
                       "database" => "foo",
                       "host"     => "localhost",
                       "pool"     => "5"
                      }
                    }
        assert_equal expected, actual
      end
    end

    class ConnectionHandlerTest < ActiveRecord::TestCase
      def setup
        @klass    = Class.new(Base)   { def self.name; 'klass';    end }
        @subklass = Class.new(@klass) { def self.name; 'subklass'; end }

        @handler = ConnectionHandler.new
        @pool    = @handler.establish_connection(@klass, Base.connection_pool.spec)
      end

      def test_retrieve_connection
        assert @handler.retrieve_connection(@klass)
      end

      def test_active_connections?
        assert !@handler.active_connections?
        assert @handler.retrieve_connection(@klass)
        assert @handler.active_connections?
        @handler.clear_active_connections!
        assert !@handler.active_connections?
      end

      def test_retrieve_connection_pool_with_ar_base
        assert_nil @handler.retrieve_connection_pool(ActiveRecord::Base)
      end

      def test_retrieve_connection_pool
        assert_not_nil @handler.retrieve_connection_pool(@klass)
      end

      def test_retrieve_connection_pool_uses_superclass_when_no_subclass_connection
        assert_not_nil @handler.retrieve_connection_pool(@subklass)
      end

      def test_retrieve_connection_pool_uses_superclass_pool_after_subclass_establish_and_remove
        sub_pool = @handler.establish_connection(@subklass, Base.connection_pool.spec)
        assert_same sub_pool, @handler.retrieve_connection_pool(@subklass)

        @handler.remove_connection @subklass
        assert_same @pool, @handler.retrieve_connection_pool(@subklass)
      end

      def test_connection_pools
        assert_deprecated do
          assert_equal({ Base.connection_pool.spec => @pool }, @handler.connection_pools)
        end
      end
    end
  end
end
