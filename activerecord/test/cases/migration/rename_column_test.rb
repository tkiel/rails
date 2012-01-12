require "cases/migration/helper"

module ActiveRecord
  class Migration
    class RenameColumnTest < ActiveRecord::TestCase
      include ActiveRecord::Migration::TestHelper

      self.use_transactional_fixtures = false

      # FIXME: this is more of an integration test with AR::Base and the
      # schema modifications.  Maybe we should move this?
      def test_add_rename
        add_column "test_models", "girlfriend", :string
        TestModel.reset_column_information

        TestModel.create :girlfriend => 'bobette'

        rename_column "test_models", "girlfriend", "exgirlfriend"

        TestModel.reset_column_information
        bob = TestModel.find(:first)

        assert_equal "bobette", bob.exgirlfriend
      end

      # FIXME: another integration test.  We should decouple this from the
      # AR::Base implementation.
      def test_rename_column_using_symbol_arguments
        add_column :test_models, :first_name, :string

        TestModel.create :first_name => 'foo'

        rename_column :test_models, :first_name, :nick_name
        TestModel.reset_column_information
        assert TestModel.column_names.include?("nick_name")
        assert_equal ['foo'], TestModel.find(:all).map(&:nick_name)
      end

      # FIXME: another integration test.  We should decouple this from the
      # AR::Base implementation.
      def test_rename_column
        add_column "test_models", "first_name", "string"

        TestModel.create :first_name => 'foo'

        rename_column "test_models", "first_name", "nick_name"
        TestModel.reset_column_information
        assert TestModel.column_names.include?("nick_name")
        assert_equal ['foo'], TestModel.find(:all).map(&:nick_name)
      end

      def test_rename_column_preserves_default_value_not_null
        add_column 'test_models', 'salary', :integer, :default => 70000

        default_before = connection.columns("test_models").find { |c| c.name == "salary" }.default
        assert_equal 70000, default_before

        rename_column "test_models", "salary", "anual_salary"

        assert TestModel.column_names.include?("anual_salary")
        default_after = connection.columns("test_models").find { |c| c.name == "anual_salary" }.default
        assert_equal 70000, default_after
      end

      def test_rename_nonexistent_column
        exception = if current_adapter?(:PostgreSQLAdapter, :OracleAdapter)
                      ActiveRecord::StatementInvalid
                    else
                      ActiveRecord::ActiveRecordError
                    end
        assert_raise(exception) do
          rename_column "test_models", "nonexistent", "should_fail"
        end
      end

      def test_rename_column_with_sql_reserved_word
        add_column 'test_models', 'first_name', :string
        rename_column "test_models", "first_name", "group"

        assert TestModel.column_names.include?("group")
      end

      def test_rename_column_with_an_index
        add_column "test_models", :hat_name, :string
        add_index :test_models, :hat_name

        # FIXME: we should test that the index goes away
        rename_column "test_models", "hat_name", "name"
      end

      def test_remove_column_with_index
        add_column "test_models", :hat_name, :string
        add_index :test_models, :hat_name

        # FIXME: we should test that the index goes away
        remove_column("test_models", "hat_size")
      end

      def test_remove_column_with_multi_column_index
        add_column "test_models", :hat_size, :integer
        add_column "test_models", :hat_style, :string, :limit => 100
        add_index "test_models", ["hat_style", "hat_size"], :unique => true

        # FIXME: we should test that the index goes away
        remove_column("test_models", "hat_size")
      end

      # FIXME: we need to test that these calls do something
      def test_change_type_of_not_null_column
        change_column "test_models", "updated_at", :datetime, :null => false
        change_column "test_models", "updated_at", :datetime, :null => false
        change_column "test_models", "updated_at", :datetime, :null => true
      end

      def test_change_column_nullability
        add_column "test_models", "funny", :boolean
        assert TestModel.columns_hash["funny"].null, "Column 'funny' must initially allow nulls"

        change_column "test_models", "funny", :boolean, :null => false, :default => true

        TestModel.reset_column_information
        refute TestModel.columns_hash["funny"].null, "Column 'funny' must *not* allow nulls at this point"

        change_column "test_models", "funny", :boolean, :null => true
        TestModel.reset_column_information
        assert TestModel.columns_hash["funny"].null, "Column 'funny' must allow nulls again at this point"
      end

      def test_change_column
        add_column 'test_models', 'age', :integer
        add_column 'test_models', 'approved', :boolean, :default => true

        label = "test_change_column Columns"
        old_columns = connection.columns(TestModel.table_name, label)

        assert old_columns.find { |c| c.name == 'age' && c.type == :integer }

        change_column "test_models", "age", :string

        new_columns = connection.columns(TestModel.table_name, label)

        refute new_columns.find { |c| c.name == 'age' and c.type == :integer }
        assert new_columns.find { |c| c.name == 'age' and c.type == :string }

        old_columns = connection.columns(TestModel.table_name, label)
        assert old_columns.find { |c|
          c.name == 'approved' && c.type == :boolean && c.default == true
        }

        change_column :test_models, :approved, :boolean, :default => false
        new_columns = connection.columns(TestModel.table_name, label)

        refute new_columns.find { |c| c.name == 'approved' and c.type == :boolean and c.default == true }
        assert new_columns.find { |c| c.name == 'approved' and c.type == :boolean and c.default == false }
        change_column :test_models, :approved, :boolean, :default => true
      end

      def test_change_column_with_nil_default
        add_column "test_models", "contributor", :boolean, :default => true
        assert TestModel.new.contributor?

        change_column "test_models", "contributor", :boolean, :default => nil
        TestModel.reset_column_information
        refute TestModel.new.contributor?
        assert_nil TestModel.new.contributor
      end

      def test_change_column_with_new_default
        add_column "test_models", "administrator", :boolean, :default => true
        assert TestModel.new.administrator?

        change_column "test_models", "administrator", :boolean, :default => false
        TestModel.reset_column_information
        refute TestModel.new.administrator?
      end

      def test_change_column_default
        add_column "test_models", "first_name", :string
        connection.change_column_default "test_models", "first_name", "Tester"

        assert_equal "Tester", TestModel.new.first_name
      end

      def test_change_column_default_to_null
        add_column "test_models", "first_name", :string
        connection.change_column_default "test_models", "first_name", nil
        assert_nil TestModel.new.first_name
      end
    end
  end
end
