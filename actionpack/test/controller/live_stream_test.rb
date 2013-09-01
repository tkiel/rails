require 'abstract_unit'
require 'active_support/concurrency/latch'

module ActionController
  class SSETest < ActionController::TestCase
    class SSETestController < ActionController::Base
      include ActionController::Live

      def basic_sse
        response.headers['Content-Type'] = 'text/event-stream'
        sse = SSE.new(response.stream)
        sse.write("{\"name\":\"John\"}")
        sse.write({ name: "Ryan" })
      ensure
        sse.close
      end

      def sse_with_event
        sse = SSE.new(response.stream, event: "send-name")
        sse.write("{\"name\":\"John\"}")
        sse.write({ name: "Ryan" })
      ensure
        sse.close
      end

      def sse_with_retry
        sse = SSE.new(response.stream, retry: 1000)
        sse.write("{\"name\":\"John\"}")
        sse.write({ name: "Ryan" }, retry: 1500)
      ensure
        sse.close
      end

      def sse_with_id
        sse = SSE.new(response.stream)
        sse.write("{\"name\":\"John\"}", id: 1)
        sse.write({ name: "Ryan" }, id: 2)
      ensure
        sse.close
      end
    end

    tests SSETestController

    def wait_for_response_stream_close
      while !response.stream.closed?
        sleep 0.01
      end
    end

    def test_basic_sse
      get :basic_sse

      wait_for_response_stream_close
      assert_match(/data: {\"name\":\"John\"}/, response.body)
      assert_match(/data: {\"name\":\"Ryan\"}/, response.body)
    end

    def test_sse_with_event_name
      get :sse_with_event

      wait_for_response_stream_close
      assert_match(/data: {\"name\":\"John\"}/, response.body)
      assert_match(/data: {\"name\":\"Ryan\"}/, response.body)
      assert_match(/event: send-name/, response.body)
    end

    def test_sse_with_retry
      get :sse_with_retry

      wait_for_response_stream_close
      first_response, second_response = response.body.split("\n\n")
      assert_match(/data: {\"name\":\"John\"}/, first_response)
      assert_match(/retry: 1000/, first_response)

      assert_match(/data: {\"name\":\"Ryan\"}/, second_response)
      assert_match(/retry: 1500/, second_response)
    end

    def test_sse_with_id
      get :sse_with_id

      wait_for_response_stream_close
      first_response, second_response = response.body.split("\n\n")
      assert_match(/data: {\"name\":\"John\"}/, first_response)
      assert_match(/id: 1/, first_response)

      assert_match(/data: {\"name\":\"Ryan\"}/, second_response)
      assert_match(/id: 2/, second_response)
    end
  end

  class LiveStreamTest < ActionController::TestCase
    class TestController < ActionController::Base
      include ActionController::Live

      attr_accessor :latch, :tc

      def self.controller_path
        'test'
      end

      def render_text
        render :text => 'zomg'
      end

      def default_header
        response.stream.write "<html><body>hi</body></html>"
        response.stream.close
      end

      def basic_stream
        response.headers['Content-Type'] = 'text/event-stream'
        %w{ hello world }.each do |word|
          response.stream.write word
        end
        response.stream.close
      end

      def blocking_stream
        response.headers['Content-Type'] = 'text/event-stream'
        %w{ hello world }.each do |word|
          response.stream.write word
          latch.await
        end
        response.stream.close
      end

      def thread_locals
        tc.assert_equal 'aaron', Thread.current[:setting]
        tc.assert_not_equal Thread.current.object_id, Thread.current[:originating_thread]

        response.headers['Content-Type'] = 'text/event-stream'
        %w{ hello world }.each do |word|
          response.stream.write word
        end
        response.stream.close
      end

      def with_stale
        render :text => 'stale' if stale?(:etag => "123")
      end

      def exception_in_view
        render 'doesntexist'
      end

      def exception_with_callback
        response.headers['Content-Type'] = 'text/event-stream'

        response.stream.on_error do
          response.stream.write %(data: "500 Internal Server Error"\n\n)
          response.stream.close
        end

        raise 'An exception occurred...'
      end

      def exception_in_exception_callback
        response.headers['Content-Type'] = 'text/event-stream'
        response.stream.on_error do
          raise 'We need to go deeper.'
        end
        response.stream.write params[:widget][:didnt_check_for_nil]
      end
    end

    tests TestController

    class TestResponse < Live::Response
      def recycle!
        initialize
      end
    end

    def build_response
      TestResponse.new
    end

    def assert_stream_closed
      assert response.stream.closed?, 'stream should be closed'
    end

    def capture_log_output
      output = StringIO.new
      old_logger, ActionController::Base.logger = ActionController::Base.logger, ActiveSupport::Logger.new(output)

      begin
        yield output
      ensure
        ActionController::Base.logger = old_logger
      end
    end

    def test_set_response!
      @controller.set_response!(@request)
      assert_kind_of(Live::Response, @controller.response)
      assert_equal @request, @controller.response.request
    end

    def test_write_to_stream
      @controller = TestController.new
      get :basic_stream
      assert_equal "helloworld", @response.body
      assert_equal 'text/event-stream', @response.headers['Content-Type']
    end

    def test_async_stream
      @controller.latch = ActiveSupport::Concurrency::Latch.new
      parts             = ['hello', 'world']

      @controller.request  = @request
      @controller.response = @response

      t = Thread.new(@response) { |resp|
        resp.stream.each do |part|
          assert_equal parts.shift, part
          ol = @controller.latch
          @controller.latch = ActiveSupport::Concurrency::Latch.new
          ol.release
        end
      }

      @controller.process :blocking_stream

      assert t.join(3), 'timeout expired before the thread terminated'
    end

    def test_thread_locals_get_copied
      @controller.tc = self
      Thread.current[:originating_thread] = Thread.current.object_id
      Thread.current[:setting]            = 'aaron'

      get :thread_locals
    end

    def test_live_stream_default_header
      @controller.request  = @request
      @controller.response = @response
      @controller.process :default_header
      _, headers, _ = @response.prepare!
      assert headers['Content-Type']
    end

    def test_render_text
      get :render_text
      assert_equal 'zomg', response.body
      assert_stream_closed
    end

    def test_exception_handling_html
      capture_log_output do |output|
        get :exception_in_view
        assert_match %r((window\.location = "/500\.html"</script></html>)$), response.body
        assert_match 'Missing template test/doesntexist', output.rewind && output.read
        assert_stream_closed
      end
    end

    def test_exception_handling_plain_text
      capture_log_output do |output|
        get :exception_in_view, format: :json
        assert_equal '', response.body
        assert_match 'Missing template test/doesntexist', output.rewind && output.read
        assert_stream_closed
      end
    end

    def test_exception_callback
      capture_log_output do |output|
        get :exception_with_callback, format: 'text/event-stream'
        assert_equal %(data: "500 Internal Server Error"\n\n), response.body
        assert_match 'An exception occurred...', output.rewind && output.read
        assert_stream_closed
      end
    end

    def test_exceptions_raised_handling_exceptions
      capture_log_output do |output|
        get :exception_in_exception_callback, format: 'text/event-stream'
        assert_equal '', response.body
        assert_match 'We need to go deeper', output.rewind && output.read
        assert_stream_closed
      end
    end

    def test_stale_without_etag
      get :with_stale
      assert_equal 200, @response.status.to_i
    end

    def test_stale_with_etag
      @request.if_none_match = Digest::MD5.hexdigest("123")
      get :with_stale
      assert_equal 304, @response.status.to_i
    end
  end
end
