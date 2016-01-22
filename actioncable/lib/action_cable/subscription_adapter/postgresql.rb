gem 'pg', '~> 0.18'
require 'pg'
require 'thread'

module ActionCable
  module SubscriptionAdapter
    class PostgreSQL < Base # :nodoc:
      def broadcast(channel, payload)
        with_connection do |pg_conn|
          pg_conn.exec("NOTIFY #{pg_conn.escape_identifier(channel)}, '#{pg_conn.escape_string(payload)}'")
        end
      end

      def subscribe(channel, callback, success_callback = nil)
        listener.add_subscriber(channel, callback, success_callback)
      end

      def unsubscribe(channel, callback)
        listener.remove_subscriber(channel, callback)
      end

      def with_connection(&block) # :nodoc:
        ActiveRecord::Base.connection_pool.with_connection do |ar_conn|
          pg_conn = ar_conn.raw_connection

          unless pg_conn.is_a?(PG::Connection)
            raise 'ActiveRecord database must be Postgres in order to use the Postgres ActionCable storage adapter'
          end

          yield pg_conn
        end
      end

      private
        def listener
          @listener ||= Listener.new(self)
        end

        class Listener < SubscriberMap
          def initialize(adapter)
            super()

            @adapter = adapter
            @queue = Queue.new

            Thread.new do
              Thread.current.abort_on_exception = true
              listen
            end
          end

          def listen
            @adapter.with_connection do |pg_conn|
              loop do
                until @queue.empty?
                  action, channel, callback = @queue.pop(true)
                  escaped_channel = pg_conn.escape_identifier(channel)

                  if action == :listen
                    pg_conn.exec("LISTEN #{escaped_channel}")
                    ::EM.next_tick(&callback) if callback
                  elsif action == :unlisten
                    pg_conn.exec("UNLISTEN #{escaped_channel}")
                  end
                end

                pg_conn.wait_for_notify(1) do |chan, pid, message|
                  broadcast(chan, message)
                end
              end
            end
          end

          def add_channel(channel, on_success)
            @queue.push([:listen, channel, on_success])
          end

          def remove_channel(channel)
            @queue.push([:unlisten, channel])
          end

          def invoke_callback(*)
            ::EM.next_tick { super }
          end
        end
    end
  end
end
