require 'abstract_unit'
require 'active_support/concurrency/latch'

module ActionController
  module Live
    class ResponseTest < ActiveSupport::TestCase
      def setup
        @response = Live::Response.new
      end

      def test_parallel
        latch = ActiveSupport::Concurrency::Latch.new

        t = Thread.new {
          @response.stream.write 'foo'
          latch.await
          @response.stream.close
        }

        @response.each do |part|
          assert_equal 'foo', part
          latch.release
        end
        assert t.join
      end

      def test_setting_body_populates_buffer
        @response.body = 'omg'
        @response.close
        assert_equal ['omg'], @response.body_parts
      end

      def test_cache_control_is_set
        @response.stream.write 'omg'
        assert_equal 'no-cache', @response.headers['Cache-Control']
      end

      def test_content_length_is_removed
        @response.headers['Content-Length'] = "1234"
        @response.stream.write 'omg'
        assert_nil @response.headers['Content-Length']
      end
    end
  end
end
