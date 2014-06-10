require 'cases/helper'
require 'support/ddl_helper'
require 'support/schema_dumping_helper'

if ActiveRecord::Base.connection.supports_foreign_keys?
module ActiveRecord
  class Migration
    class ForeignKeyTest < ActiveRecord::TestCase
      include DdlHelper
      include SchemaDumpingHelper

      class Rocket < ActiveRecord::Base
      end

      class Astronaut < ActiveRecord::Base
      end

      setup do
        @connection = ActiveRecord::Base.connection
        @connection.create_table "rockets" do |t|
          t.string :name
        end

        @connection.create_table "astronauts" do |t|
          t.string :name
          t.references :rocket
        end
      end

      teardown do
        if defined?(@connection)
          @connection.execute "DROP TABLE IF EXISTS astronauts"
          @connection.execute "DROP TABLE IF EXISTS rockets"
        end
      end

      def test_foreign_keys
        foreign_keys = @connection.foreign_keys("fk_test_has_fk")
        assert_equal 1, foreign_keys.size

        fk = foreign_keys.first
        assert_equal "fk_test_has_fk", fk.from_table
        assert_equal "fk_test_has_pk", fk.to_table
        assert_equal "fk_id", fk.column
        assert_equal "id", fk.primary_key
        assert_equal "fk_name", fk.name
      end

      def test_add_foreign_key
        @connection.add_foreign_key :astronauts, :rockets, column: "rocket_id"

        foreign_keys = @connection.foreign_keys("astronauts")
        assert_equal 1, foreign_keys.size

        fk = foreign_keys.first
        assert_equal "astronauts", fk.from_table
        assert_equal "rockets", fk.to_table
        assert_equal "rocket_id", fk.column
        assert_equal "id", fk.primary_key
        assert_equal "astronauts_rocket_id_fk", fk.name
      end

      def test_add_foreign_key_with_non_standard_primary_key
        with_example_table @connection, "space_shuttles", "pk integer PRIMARY KEY" do
          @connection.add_foreign_key(:astronauts, :space_shuttles,
                                      column: "rocket_id", primary_key: "pk", name: "custom_pk")

          foreign_keys = @connection.foreign_keys("astronauts")
          assert_equal 1, foreign_keys.size

          fk = foreign_keys.first
          assert_equal "astronauts", fk.from_table
          assert_equal "space_shuttles", fk.to_table
          assert_equal "pk", fk.primary_key

          @connection.remove_foreign_key :astronauts, name: "custom_pk"
        end
      end

      def test_remove_foreign_key
        @connection.add_foreign_key :astronauts, :rockets, column: "rocket_id"

        assert_equal 1, @connection.foreign_keys("astronauts").size
        @connection.remove_foreign_key :astronauts, column: "rocket_id"
        assert_equal [], @connection.foreign_keys("astronauts")
      end

      def test_remove_foreign_key_by_name
        @connection.add_foreign_key :astronauts, :rockets, column: "rocket_id", name: "fancy_named_fk"

        assert_equal 1, @connection.foreign_keys("astronauts").size
        @connection.remove_foreign_key :astronauts, name: "fancy_named_fk"
        assert_equal [], @connection.foreign_keys("astronauts")
      end

      def test_schema_dumping
        output = dump_table_schema "fk_test_has_fk"
        assert_match %r{\s+add_foreign_key "fk_test_has_fk", "fk_test_has_pk", column: "fk_id", primary_key: "id", name: "fk_name"$}, output
      end
    end
  end
end
end
