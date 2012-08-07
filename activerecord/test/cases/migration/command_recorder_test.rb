require "cases/helper"

module ActiveRecord
  class Migration
    class CommandRecorderTest < ActiveRecord::TestCase
      def setup
        @recorder = CommandRecorder.new
      end

      def test_respond_to_delegates
        recorder = CommandRecorder.new(Class.new {
          def america; end
        }.new)
        assert recorder.respond_to?(:america)
      end

      def test_send_calls_super
        assert_raises(NoMethodError) do
          @recorder.send(:non_existing_method, :horses)
        end
      end

      def test_send_delegates_to_record
        recorder = CommandRecorder.new(Class.new {
          def create_table(name); end
        }.new)
        assert recorder.respond_to?(:create_table), 'respond_to? create_table'
        recorder.send(:create_table, :horses)
        assert_equal [[:create_table, [:horses], nil]], recorder.commands
      end

      def test_unknown_commands_delegate
        recorder = CommandRecorder.new(stub(:foo => 'bar'))
        assert_equal 'bar', recorder.foo
      end

      def test_unknown_commands_raise_exception_if_they_cannot_delegate
        assert_raises(ActiveRecord::IrreversibleMigration) do
          @recorder.inverse_of :execute, ['some sql']
        end
      end

      def test_record
        @recorder.record :create_table, [:system_settings]
        assert_equal 1, @recorder.commands.length
      end

      def test_inverted_commands_are_reversed
        @recorder.revert do
          @recorder.record :create_table, [:hello]
          @recorder.record :create_table, [:world]
        end
        tables = @recorder.commands.map(&:last)
        assert_equal [[:world], [:hello]], tables
      end

      def test_revert_order
        block = Proc.new{|t| t.string :name }
        @recorder.instance_eval do
          create_table("apples", &block)
          revert do
            create_table("bananas", &block)
            revert do
              create_table("clementines")
              create_table("dates")
            end
            create_table("elderberries")
          end
          revert do
            create_table("figs")
            create_table("grapes")
          end
        end
        assert_equal [[:create_table, ["apples"], block], [:drop_table, ["elderberries"]],
                      [:create_table, ["clementines"], nil], [:create_table, ["dates"], nil],
                      [:drop_table, ["bananas"]], [:drop_table, ["grapes"]],
                      [:drop_table, ["figs"]]], @recorder.commands
      end


      def test_invert_create_table
        @recorder.revert do
          @recorder.record :create_table, [:system_settings]
        end
        drop_table = @recorder.commands.first
        assert_equal [:drop_table, [:system_settings]], drop_table
      end

      def test_invert_create_table_with_options
        drop_table = @recorder.inverse_of :create_table, [:people_reminders, id: false]
        assert_equal [:drop_table, [:people_reminders]], drop_table
      end

      def test_invert_create_join_table
        drop_table = @recorder.inverse_of :create_join_table, [:musics, :artists]
        assert_equal [:drop_table, [:artists_musics]], drop_table
      end

      def test_invert_create_join_table_with_table_name
        drop_table = @recorder.inverse_of :create_join_table, [:musics, :artists, table_name: :catalog]
        assert_equal [:drop_table, [:catalog]], drop_table
      end

      def test_invert_rename_table
        rename = @recorder.inverse_of :rename_table, [:old, :new]
        assert_equal [:rename_table, [:new, :old]], rename
      end

      def test_invert_add_column
        remove = @recorder.inverse_of :add_column, [:table, :column, :type, {}]
        assert_equal [:remove_column, [:table, :column]], remove
      end

      def test_invert_rename_column
        rename = @recorder.inverse_of :rename_column, [:table, :old, :new]
        assert_equal [:rename_column, [:table, :new, :old]], rename
      end

      def test_invert_add_index
        remove = @recorder.inverse_of :add_index, [:table, [:one, :two], options: true]
        assert_equal [:remove_index, [:table, {:column => [:one, :two]}]], remove
      end

      def test_invert_add_index_with_name
        remove = @recorder.inverse_of :add_index, [:table, [:one, :two], name: "new_index"]
        assert_equal [:remove_index, [:table, {:name => "new_index"}]], remove
      end

      def test_invert_add_index_with_no_options
        remove = @recorder.inverse_of :add_index, [:table, [:one, :two]]
        assert_equal [:remove_index, [:table, {:column => [:one, :two]}]], remove
      end

      def test_invert_rename_index
        rename = @recorder.inverse_of :rename_index, [:table, :old, :new]
        assert_equal [:rename_index, [:table, :new, :old]], rename
      end

      def test_invert_add_timestamps
        remove = @recorder.inverse_of :add_timestamps, [:table]
        assert_equal [:remove_timestamps, [:table]], remove
      end

      def test_invert_remove_timestamps
        add = @recorder.inverse_of :remove_timestamps, [:table]
        assert_equal [:add_timestamps, [:table]], add
      end

      def test_invert_add_reference
        remove = @recorder.inverse_of :add_reference, [:table, :taggable, { polymorphic: true }]
        assert_equal [:remove_reference, [:table, :taggable, { polymorphic: true }]], remove
      end

      def test_invert_add_belongs_to_alias
        remove = @recorder.inverse_of :add_belongs_to, [:table, :user]
        assert_equal [:remove_reference, [:table, :user]], remove
      end

      def test_invert_remove_reference
        add = @recorder.inverse_of :remove_reference, [:table, :taggable, { polymorphic: true }]
        assert_equal [:add_reference, [:table, :taggable, { polymorphic: true }]], add
      end

      def test_invert_remove_belongs_to_alias
        add = @recorder.inverse_of :remove_belongs_to, [:table, :user]
        assert_equal [:add_reference, [:table, :user]], add
      end
    end
  end
end
