# frozen_string_literal: true

require "abstract_unit"
require "stringio"
require "active_support/key_generator"
require "active_support/messages/rotation_configuration"

class CookieStoreTest < ActionDispatch::IntegrationTest
  SessionKey = "_myapp_session"
  SessionSecret = "b3c631c314c0bbca50c1b2843150fe33"
  SessionSalt   = "authenticated encrypted cookie"

  Generator = ActiveSupport::KeyGenerator.new(SessionSecret, iterations: 1000)
  Rotations = ActiveSupport::Messages::RotationConfiguration.new

  Encryptor = ActiveSupport::MessageEncryptor.new \
    Generator.generate_key(SessionSalt, 32), cipher: "aes-256-gcm", serializer: Marshal

  class TestController < ActionController::Base
    def no_session_access
      head :ok
    end

    def persistent_session_id
      render plain: session[:session_id]
    end

    def set_session_value
      session[:foo] = "bar"
      render body: nil
    end

    def get_session_value
      render plain: "foo: #{session[:foo].inspect}"
    end

    def get_session_id
      render plain: "id: #{request.session.id}"
    end

    def get_class_after_reset_session
      reset_session
      render plain: "class: #{session.class}"
    end

    def call_session_clear
      session.clear
      head :ok
    end

    def call_reset_session
      reset_session
      head :ok
    end

    def raise_data_overflow
      session[:foo] = "bye!" * 1024
      head :ok
    end

    def change_session_id
      request.session.options[:id] = nil
      get_session_id
    end

    def renew_session_id
      request.session_options[:renew] = true
      head :ok
    end
  end

  def parse_cookie_from_header
    cookie_matches = headers["Set-Cookie"].match(/#{SessionKey}=([^;]+)/)
    cookie_matches && cookie_matches[1]
  end

  def assert_session_cookie(cookie_string, contents)
    assert_includes headers["Set-Cookie"], cookie_string

    session_value = parse_cookie_from_header
    session_data = Encryptor.decrypt_and_verify(Rack::Utils.unescape(session_value)) rescue nil

    assert_not_nil session_data, "session failed to decrypt"
    assert_equal session_data.slice(*contents.keys), contents
  end

  def test_setting_session_value
    with_test_route_set do
      get "/set_session_value"

      assert_response :success
      assert_session_cookie "path=/; HttpOnly", "foo" => "bar"
    end
  end

  def test_getting_session_value
    with_test_route_set do
      get "/set_session_value"
      get "/get_session_value"

      assert_response :success
      assert_equal 'foo: "bar"', response.body
    end
  end

  def test_getting_session_id
    with_test_route_set do
      get "/set_session_value"
      get "/persistent_session_id"

      assert_response :success
      assert_equal 32, response.body.size
      session_id = response.body

      get "/get_session_id"
      assert_response :success
      assert_equal "id: #{session_id}", response.body, "should be able to read session id without accessing the session hash"
    end
  end

  def test_disregards_tampered_sessions
    with_test_route_set do
      encryptor = ActiveSupport::MessageEncryptor.new("A" * 32, cipher: "aes-256-gcm", serializer: Marshal)

      cookies[SessionKey] = encryptor.encrypt_and_sign("foo" => "bar", "session_id" => "abc")

      get "/get_session_value"

      assert_response :success
      assert_equal "foo: nil", response.body
    end
  end

  def test_does_not_set_secure_cookies_over_http
    with_test_route_set(secure: true) do
      get "/set_session_value"
      assert_response :success
      assert_nil headers["Set-Cookie"]
    end
  end

  def test_properly_renew_cookies
    with_test_route_set do
      get "/set_session_value"
      get "/persistent_session_id"
      session_id = response.body
      get "/renew_session_id"
      get "/persistent_session_id"
      assert_not_equal response.body, session_id
    end
  end

  def test_does_set_secure_cookies_over_https
    with_test_route_set(secure: true) do
      get "/set_session_value", headers: { "HTTPS" => "on" }

      assert_response :success
      assert_session_cookie "path=/; secure; HttpOnly", "foo" => "bar"
    end
  end

  # {:foo=>#<SessionAutoloadTest::Foo bar:"baz">, :session_id=>"ce8b0752a6ab7c7af3cdb8a80e6b9e46"}
  EncryptedSerializedCookie = "9RZ2Fij0qLveUwM4s+CCjGqhpjyUC8jiBIf/AiBr9M3TB8xh2vQZtvSOMfN3uf6oYbbpIDHAcOFIEl69FcW1ozQYeSrCLonYCazoh34ZdYskIQfGwCiSYleVXG1OD9Z4jFqeVArw4Ewm0paOOPLbN1rc6A==--I359v/KWdZ1ok0ey--JFFhuPOY7WUo6tB/eP05Aw=="

  def test_deserializes_unloaded_classes_on_get_id
    with_test_route_set do
      with_autoload_path "session_autoload_test" do
        cookies[SessionKey] = EncryptedSerializedCookie
        get "/get_session_id"
        assert_response :success
        assert_equal "id: ce8b0752a6ab7c7af3cdb8a80e6b9e46", response.body, "should auto-load unloaded class"
      end
    end
  end

  def test_deserializes_unloaded_classes_on_get_value
    with_test_route_set do
      with_autoload_path "session_autoload_test" do
        cookies[SessionKey] = EncryptedSerializedCookie
        get "/get_session_value"
        assert_response :success
        assert_equal 'foo: #<SessionAutoloadTest::Foo bar:"baz">', response.body, "should auto-load unloaded class"
      end
    end
  end

  def test_close_raises_when_data_overflows
    with_test_route_set do
      assert_raise(ActionDispatch::Cookies::CookieOverflow) {
        get "/raise_data_overflow"
      }
    end
  end

  def test_doesnt_write_session_cookie_if_session_is_not_accessed
    with_test_route_set do
      get "/no_session_access"
      assert_response :success
      assert_nil headers["Set-Cookie"]
    end
  end

  def test_doesnt_write_session_cookie_if_session_is_unchanged
    with_test_route_set do
      cookies[SessionKey] = "BAh7BjoIZm9vIghiYXI%3D--" \
        "fef868465920f415f2c0652d6910d3af288a0367"
      get "/no_session_access"
      assert_response :success
      assert_nil headers["Set-Cookie"]
    end
  end

  def test_setting_session_value_after_session_reset
    with_test_route_set do
      get "/set_session_value"
      assert_response :success
      session_payload = response.body
      assert_session_cookie "path=/; HttpOnly", "foo" => "bar"

      get "/call_reset_session"
      assert_response :success
      assert_not_equal [], headers["Set-Cookie"]
      assert_not_nil session_payload
      assert_not_equal session_payload, cookies[SessionKey]

      get "/get_session_value"
      assert_response :success
      assert_equal "foo: nil", response.body
    end
  end

  def test_class_type_after_session_reset
    with_test_route_set do
      get "/set_session_value"
      assert_response :success
      assert_session_cookie "path=/; HttpOnly", "foo" => "bar"

      get "/get_class_after_reset_session"
      assert_response :success
      assert_not_equal [], headers["Set-Cookie"]
      assert_equal "class: ActionDispatch::Request::Session", response.body
    end
  end

  def test_getting_from_nonexistent_session
    with_test_route_set do
      get "/get_session_value"
      assert_response :success
      assert_equal "foo: nil", response.body
      assert_nil headers["Set-Cookie"], "should only create session on write, not read"
    end
  end

  def test_setting_session_value_after_session_clear
    with_test_route_set do
      get "/set_session_value"
      assert_response :success
      assert_session_cookie "path=/; HttpOnly", "foo" => "bar"

      get "/call_session_clear"
      assert_response :success

      get "/get_session_value"
      assert_response :success
      assert_equal "foo: nil", response.body
    end
  end

  def test_persistent_session_id
    with_test_route_set do
      get "/set_session_value"
      get "/persistent_session_id"
      assert_response :success
      assert_equal 32, response.body.size
      session_id = response.body
      get "/persistent_session_id"
      assert_equal session_id, response.body
      reset!
      get "/persistent_session_id"
      assert_not_equal session_id, response.body
    end
  end

  def test_setting_session_id_to_nil_is_respected
    with_test_route_set do
      get "/set_session_value"
      get "/get_session_id"
      sid = response.body
      assert_equal 36, sid.size

      get "/change_session_id"
      assert_not_equal sid, response.body
    end
  end

  def test_session_store_with_expire_after
    with_test_route_set(expire_after: 5.hours) do
      # First request accesses the session
      time = Time.local(2008, 4, 24)

      Time.stub :now, time do
        expected_expiry = (time + 5.hours).gmtime.strftime("%a, %d %b %Y %H:%M:%S -0000")

        get "/set_session_value"

        assert_response :success
        assert_session_cookie "path=/; expires=#{expected_expiry}; HttpOnly", "foo" => "bar"
      end

      # Second request does not access the session
      time = time + 3.hours
      Time.stub :now, time do
        expected_expiry = (time + 5.hours).gmtime.strftime("%a, %d %b %Y %H:%M:%S -0000")

        get "/no_session_access"

        assert_response :success
        assert_session_cookie "path=/; expires=#{expected_expiry}; HttpOnly", "foo" => "bar"
      end
    end
  end

  def test_session_store_with_expire_after_does_not_accept_expired_session
    with_test_route_set(expire_after: 5.hours) do
      # First request accesses the session
      time = Time.local(2017, 11, 12)

      Time.stub :now, time do
        expected_expiry = (time + 5.hours).gmtime.strftime("%a, %d %b %Y %H:%M:%S -0000")

        get "/set_session_value"
        get "/get_session_value"

        assert_response :success
        assert_equal 'foo: "bar"', response.body
        assert_session_cookie "path=/; expires=#{expected_expiry}; HttpOnly", "foo" => "bar"
      end

      # Second request is beyond the expiry time and the session is invalidated
      time += 5.hours + 1.minute

      Time.stub :now, time do
        get "/get_session_value"

        assert_response :success
        assert_equal "foo: nil", response.body
      end
    end
  end

  def test_session_store_with_explicit_domain
    with_test_route_set(domain: "example.es") do
      get "/set_session_value"
      assert_match(/domain=example\.es/, headers["Set-Cookie"])
      headers["Set-Cookie"]
    end
  end

  def test_session_store_without_domain
    with_test_route_set do
      get "/set_session_value"
      assert_no_match(/domain\=/, headers["Set-Cookie"])
    end
  end

  def test_session_store_with_nil_domain
    with_test_route_set(domain: nil) do
      get "/set_session_value"
      assert_no_match(/domain\=/, headers["Set-Cookie"])
    end
  end

  def test_session_store_with_all_domains
    with_test_route_set(domain: :all) do
      get "/set_session_value"
      assert_match(/domain=\.example\.com/, headers["Set-Cookie"])
    end
  end

  private

    # Overwrite get to send SessionSecret in env hash
    def get(path, *args)
      args[0] ||= {}
      args[0][:headers] ||= {}
      args[0][:headers].tap do |config|
        config["action_dispatch.secret_key_base"] = SessionSecret
        config["action_dispatch.authenticated_encrypted_cookie_salt"] = SessionSalt
        config["action_dispatch.use_authenticated_cookie_encryption"] = true

        config["action_dispatch.key_generator"] ||= Generator
        config["action_dispatch.cookies_rotations"] ||= Rotations
      end

      super(path, *args)
    end

    def with_test_route_set(options = {})
      with_routing do |set|
        set.draw do
          ActiveSupport::Deprecation.silence do
            get ":action", to: ::CookieStoreTest::TestController
          end
        end

        options = { key: SessionKey }.merge!(options)

        @app = self.class.build_app(set) do |middleware|
          middleware.use ActionDispatch::Session::CookieStore, options
          middleware.delete ActionDispatch::ShowExceptions
        end

        yield
      end
    end
end
