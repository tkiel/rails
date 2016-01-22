module ActionCable
  module SubscriptionAdapter
    class Inline < Base # :nodoc:
      def broadcast(channel, payload)
        subscriber_map.broadcast(channel, payload)
      end

      def subscribe(channel, callback, success_callback = nil)
        subscriber_map.add_subscriber(channel, callback, success_callback)
      end

      def unsubscribe(channel, callback)
        subscriber_map.remove_subscriber(channel, callback)
      end

      private
        def subscriber_map
          @subscriber_map ||= SubscriberMap.new
        end
    end
  end
end
