# frozen_string_literal: true

require "test_helper"

class SimpleConnection < ActionCable::Connection::Base
  identified_by :user_id

  class << self
    attr_accessor :disconnected_user_id
  end

  def connect
    self.user_id = request.params[:user_id] || cookies[:user_id]
  end

  def disconnect
    self.class.disconnected_user_id = user_id
  end
end

class ConnectionSimpleTest < ActionCable::Connection::TestCase
  tests SimpleConnection

  def test_connected
    connect

    assert_nil connection.user_id
  end

  def test_url_params
    connect "/cable?user_id=323"

    assert_equal "323", connection.user_id
  end

  def test_params
    connect params: { user_id: 323 }

    assert_equal "323", connection.user_id
  end

  def test_plain_cookie
    cookies["user_id"] = "456"

    connect

    assert_equal "456", connection.user_id
  end

  def test_disconnect
    cookies["user_id"] = "456"

    connect

    assert_equal "456", connection.user_id

    disconnect

    assert_equal "456", SimpleConnection.disconnected_user_id
  end
end

class Connection < ActionCable::Connection::Base
  identified_by :current_user_id
  identified_by :token

  class << self
    attr_accessor :disconnected_user_id
  end

  def connect
    self.current_user_id = verify_user
    self.token = request.headers["X-API-TOKEN"]
    logger.add_tags("ActionCable")
  end

  private

    def verify_user
      reject_unauthorized_connection unless cookies.signed[:user_id].present?
      cookies.signed[:user_id]
    end
end

class ConnectionTest < ActionCable::Connection::TestCase
  def test_connected_with_signed_cookies_and_headers
    cookies.signed["user_id"] = "456"

    connect headers: { "X-API-TOKEN" => "abc" }

    assert_equal "abc", connection.token
    assert_equal "456", connection.current_user_id
  end

  def test_connected_when_no_signed_cookies_set
    cookies["user_id"] = "456"

    assert_reject_connection { connect }
  end

  def test_connection_rejected
    assert_reject_connection { connect }
  end
end

class EncryptedCookiesConnection < ActionCable::Connection::Base
  identified_by :user_id

  def connect
    self.user_id = verify_user
  end

  private

    def verify_user
      reject_unauthorized_connection unless cookies.encrypted[:user_id].present?
      cookies.encrypted[:user_id]
    end
end

class EncryptedCookiesConnectionTest < ActionCable::Connection::TestCase
  tests EncryptedCookiesConnection

  def test_connected_with_encrypted_cookies
    cookies.encrypted["user_id"] = "456"

    connect

    assert_equal "456", connection.user_id
  end

  def test_connection_rejected
    assert_reject_connection { connect }
  end
end

class SessionConnection < ActionCable::Connection::Base
  identified_by :user_id

  def connect
    self.user_id = verify_user
  end

  private

    def verify_user
      reject_unauthorized_connection unless request.session[:user_id].present?
      request.session[:user_id]
    end
end

class SessionConnectionTest < ActionCable::Connection::TestCase
  tests SessionConnection

  def test_connected_with_encrypted_cookies
    connect session: { user_id: "789" }
    assert_equal "789", connection.user_id
  end

  def test_connection_rejected
    assert_reject_connection { connect }
  end
end

class EnvConnection < ActionCable::Connection::Base
  identified_by :user

  def connect
    self.user = verify_user
  end

  private

    def verify_user
      # Warden-like authentication
      reject_unauthorized_connection unless env["authenticator"]&.user.present?
      env["authenticator"].user
    end
end

class EnvConnectionTest < ActionCable::Connection::TestCase
  tests EnvConnection

  def test_connected_with_env
    connect env: { "authenticator" => OpenStruct.new(user: "David") }
    assert_equal "David", connection.user
  end

  def test_connection_rejected
    assert_reject_connection { connect }
  end
end
