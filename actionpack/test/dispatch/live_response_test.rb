require 'abstract_unit'
require 'active_support/concurrency/latch'

module ActionController
  module Live
    class ResponseTest < ActiveSupport::TestCase
      def setup
        @response = Live::Response.new
        @response.request = ActionDispatch::Request.new({}) #yolo
      end

      def test_header_merge
        header = @response.header.merge('Foo' => 'Bar')
        assert_kind_of(ActionController::Live::Response::Header, header)
        assert_not_equal header, @response.header
      end

      def test_initialize_with_default_headers
        r = Class.new(Live::Response) do
          def self.default_headers
            { 'omg' => 'g' }
          end
        end

        header = r.new.header
        assert_kind_of(ActionController::Live::Response::Header, header)
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

      def test_headers_cannot_be_written_after_write
        @response.stream.write 'omg'

        assert @response.headers.frozen?
        e = assert_raises(ActionDispatch::IllegalStateError) do
          @response.headers['Content-Length'] = "zomg"
        end

        assert_equal 'header already sent', e.message
      end

      def test_headers_cannot_be_written_after_close
        @response.stream.close

        assert @response.headers.frozen?
        e = assert_raises(ActionDispatch::IllegalStateError) do
          @response.headers['Content-Length'] = "zomg"
        end
        assert_equal 'header already sent', e.message
      end
    end
  end
end
