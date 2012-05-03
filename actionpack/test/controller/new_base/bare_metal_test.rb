require "abstract_unit"

module BareMetalTest
  class BareController < ActionController::Metal
    def index
      self.response_body = "Hello world"
    end
  end

  class BareTest < ActiveSupport::TestCase
    test "response body is a Rack-compatible response" do
      status, headers, body = BareController.action(:index).call(Rack::MockRequest.env_for("/"))
      assert_equal 200, status
      string = ""

      body.each do |part|
        assert part.is_a?(String), "Each part of the body must be a String"
        string << part
      end

      assert_kind_of Hash, headers, "Headers must be a Hash"
      assert headers["Content-Type"], "Content-Type must exist"

      assert_equal "Hello world", string
    end

    test "response_body value is wrapped in an array when the value is a String" do
      controller = BareController.new
      controller.index
      assert_equal ["Hello world"], controller.response_body
    end
  end

  class HeadController < ActionController::Metal
    include ActionController::Head

    def index
      head :not_found
    end

    def continue
      self.content_type = "text/html"
      head 100
    end

    def switching_protocols
      self.content_type = "text/html"
      head 101
    end

    def processing
      self.content_type = "text/html"
      head 102
    end

    def no_content
      self.content_type = "text/html"
      head 204
    end

    def reset_content
      self.content_type = "text/html"
      head 205
    end

    def not_modified
      self.content_type = "text/html"
      head 304
    end
  end

  class HeadTest < ActiveSupport::TestCase
    test "head works on its own" do
      status = HeadController.action(:index).call(Rack::MockRequest.env_for("/")).first
      assert_equal 404, status
    end

    test "head :continue (100) does not return a content-type header" do
      headers = HeadController.action(:continue).call(Rack::MockRequest.env_for("/")).second
      assert_nil headers['Content-Type']
    end

    test "head :continue (101) does not return a content-type header" do
      headers = HeadController.action(:continue).call(Rack::MockRequest.env_for("/")).second
      assert_nil headers['Content-Type']
    end

    test "head :processing (102) does not return a content-type header" do
      headers = HeadController.action(:processing).call(Rack::MockRequest.env_for("/")).second
      assert_nil headers['Content-Type']
    end

    test "head :no_content (204) does not return a content-type header" do
      headers = HeadController.action(:no_content).call(Rack::MockRequest.env_for("/")).second
      assert_nil headers['Content-Type']
    end

    test "head :reset_content (205) does not return a content-type header" do
      headers = HeadController.action(:reset_content).call(Rack::MockRequest.env_for("/")).second
      assert_nil headers['Content-Type']
    end

    test "head :not_modified (304) does not return a content-type header" do
      headers = HeadController.action(:not_modified).call(Rack::MockRequest.env_for("/")).second
      assert_nil headers['Content-Type']
    end
  end

  class BareControllerTest < ActionController::TestCase
    test "GET index" do
      get :index
      assert_equal "Hello world", @response.body
    end
  end
end
