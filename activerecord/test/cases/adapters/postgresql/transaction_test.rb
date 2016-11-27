require "cases/helper"
require "support/connection_helper"
require "concurrent/atomic/cyclic_barrier"

module ActiveRecord
  class PostgresqlTransactionTest < ActiveRecord::PostgreSQLTestCase
    self.use_transactional_tests = false

    class Sample < ActiveRecord::Base
      self.table_name = "samples"
    end

    setup do
      @connection = ActiveRecord::Base.connection

      @connection.transaction do
        @connection.drop_table "samples", if_exists: true
        @connection.create_table("samples") do |t|
          t.integer "value"
        end
      end

      Sample.reset_column_information
    end

    teardown do
      @connection.drop_table "samples", if_exists: true
    end

    test "raises SerializationFailure when a serialization failure occurs" do
      assert_raises(ActiveRecord::SerializationFailure) do
        before = Concurrent::CyclicBarrier.new(2)
        after = Concurrent::CyclicBarrier.new(2)

        thread = Thread.new do
          Thread.current.abort_on_exception = false

          with_warning_suppression do
            Sample.transaction isolation: :serializable do
              before.wait
              Sample.create value: Sample.sum(:value)
              after.wait
            end
          end
        end

        begin
          with_warning_suppression do
            Sample.transaction isolation: :serializable do
              before.wait
              Sample.create value: Sample.sum(:value)
              after.wait
            end
          end
        ensure
          thread.join
        end
      end
    end

    test "raises Deadlocked when a deadlock is encountered" do
      with_warning_suppression do
        assert_raises(ActiveRecord::Deadlocked) do
          barrier = Concurrent::CyclicBarrier.new(2)

          s1 = Sample.create value: 1
          s2 = Sample.create value: 2

          thread = Thread.new do
            Thread.current.abort_on_exception = false

            Sample.transaction do
              s1.lock!
              barrier.wait
              s2.update_attributes value: 1
            end
          end

          begin
            Sample.transaction do
              s2.lock!
              barrier.wait
              s1.update_attributes value: 2
            end
          ensure
            thread.join
          end
        end
      end
    end

    protected

      def with_warning_suppression
        log_level = ActiveRecord::Base.connection.client_min_messages
        ActiveRecord::Base.connection.client_min_messages = "error"
        yield
      ensure
        ActiveRecord::Base.connection.client_min_messages = log_level
      end
  end
end
