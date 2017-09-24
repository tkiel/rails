# frozen_string_literal: true

require "isolation/abstract_unit"
require "rack/test"

module ApplicationTests
  class CookiesTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::Isolation
    include Rack::Test::Methods

    def new_app
      File.expand_path("#{app_path}/../new_app")
    end

    def setup
      build_app
      FileUtils.rm_rf("#{app_path}/config/environments")
    end

    def app
      Rails.application
    end

    def teardown
      teardown_app
      FileUtils.rm_rf(new_app) if File.directory?(new_app)
    end

    test "always_write_cookie is true by default in development" do
      require "rails"
      Rails.env = "development"
      require "#{app_path}/config/environment"
      assert_equal true, ActionDispatch::Cookies::CookieJar.always_write_cookie
    end

    test "always_write_cookie is false by default in production" do
      require "rails"
      Rails.env = "production"
      require "#{app_path}/config/environment"
      assert_equal false, ActionDispatch::Cookies::CookieJar.always_write_cookie
    end

    test "always_write_cookie can be overridden" do
      add_to_config <<-RUBY
        config.action_dispatch.always_write_cookie = false
      RUBY

      require "rails"
      Rails.env = "development"
      require "#{app_path}/config/environment"
      assert_equal false, ActionDispatch::Cookies::CookieJar.always_write_cookie
    end

    test "signed cookies with SHA512 digest and rotated out SHA256 and SHA1 digests" do
      skip "@kaspth will fix this"

      key_gen_sha1 = ActiveSupport::KeyGenerator.new("legacy sha1 secret", iterations: 1000)
      key_gen_sha256 = ActiveSupport::KeyGenerator.new("legacy sha256 secret", iterations: 1000)

      verifer_sha1 = ActiveSupport::MessageVerifier.new(key_gen_sha1.generate_key("sha1 salt"), digest: :SHA1)
      verifer_sha256 = ActiveSupport::MessageVerifier.new(key_gen_sha256.generate_key("sha256 salt"), digest: :SHA256)

      app_file "config/routes.rb", <<-RUBY
        Rails.application.routes.draw do
          get  ':controller(/:action)'
          post ':controller(/:action)'
        end
      RUBY

      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          protect_from_forgery with: :null_session

          def write_raw_cookie_sha1
            cookies[:signed_cookie] = "#{verifer_sha1.generate("signed cookie")}"
            head :ok
          end

          def write_raw_cookie_sha256
            cookies[:signed_cookie] = "#{verifer_sha256.generate("signed cookie")}"
            head :ok
          end

          def read_signed
            render plain: cookies.signed[:signed_cookie].inspect
          end

          def read_raw_cookie
            render plain: cookies[:signed_cookie]
          end
        end
      RUBY

      add_to_config <<-RUBY
        config.action_dispatch.cookies_rotations.rotate :signed,
          digest: "SHA1", secret: "legacy sha1 secret", salt: "sha1 salt"

        config.action_dispatch.cookies_rotations.rotate :signed,
          digest: "SHA256", secret: "legacy sha256 secret", salt: "sha256 salt"

        config.action_dispatch.signed_cookie_digest = "SHA512"
        config.action_dispatch.signed_cookie_salt = "sha512 salt"
      RUBY

      require "#{app_path}/config/environment"

      verifer_sha512 = ActiveSupport::MessageVerifier.new(app.key_generator.generate_key("sha512 salt"), digest: :SHA512)

      get "/foo/write_raw_cookie_sha1"
      get "/foo/read_signed"
      assert_equal "signed cookie".inspect, last_response.body

      get "/foo/read_raw_cookie"
      assert_equal "signed cookie", verifer_sha512.verify(last_response.body)

      get "/foo/write_raw_cookie_sha256"
      get "/foo/read_signed"
      assert_equal "signed cookie".inspect, last_response.body

      get "/foo/read_raw_cookie"
      assert_equal "signed cookie", verifer_sha512.verify(last_response.body)
    end

    test "encrypted cookies with multiple rotated out ciphers" do
      skip "@kaspth will fix this"

      key_gen_one = ActiveSupport::KeyGenerator.new("legacy secret one", iterations: 1000)
      key_gen_two = ActiveSupport::KeyGenerator.new("legacy secret two", iterations: 1000)

      encryptor_one = ActiveSupport::MessageEncryptor.new(key_gen_one.generate_key("salt one", 32), cipher: "aes-256-gcm")
      encryptor_two = ActiveSupport::MessageEncryptor.new(key_gen_two.generate_key("salt two", 32), cipher: "aes-256-gcm")

      app_file "config/routes.rb", <<-RUBY
        Rails.application.routes.draw do
          get  ':controller(/:action)'
          post ':controller(/:action)'
        end
      RUBY

      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          protect_from_forgery with: :null_session

          def write_raw_cookie_one
            cookies[:encrypted_cookie] = "#{encryptor_one.encrypt_and_sign("encrypted cookie")}"
            head :ok
          end

          def write_raw_cookie_two
            cookies[:encrypted_cookie] = "#{encryptor_two.encrypt_and_sign("encrypted cookie")}"
            head :ok
          end

          def read_encrypted
            render plain: cookies.encrypted[:encrypted_cookie].inspect
          end

          def read_raw_cookie
            render plain: cookies[:encrypted_cookie]
          end
        end
      RUBY

      add_to_config <<-RUBY
        config.action_dispatch.use_authenticated_cookie_encryption = true
        config.action_dispatch.encrypted_cookie_cipher = "aes-256-gcm"
        config.action_dispatch.authenticated_encrypted_cookie_salt = "salt"

        config.action_dispatch.cookies_rotations.rotate :encrypted,
          cipher: "aes-256-gcm", secret: "legacy secret one", salt: "salt one"

        config.action_dispatch.cookies_rotations.rotate :encrypted,
          cipher: "aes-256-gcm", secret: "legacy secret two", salt: "salt two"
      RUBY

      require "#{app_path}/config/environment"

      encryptor = ActiveSupport::MessageEncryptor.new(app.key_generator.generate_key("salt", 32), cipher: "aes-256-gcm")

      get "/foo/write_raw_cookie_one"
      get "/foo/read_encrypted"
      assert_equal "encrypted cookie".inspect, last_response.body

      get "/foo/read_raw_cookie"
      assert_equal "encrypted cookie", encryptor.decrypt_and_verify(last_response.body)

      get "/foo/write_raw_cookie_sha256"
      get "/foo/read_encrypted"
      assert_equal "encrypted cookie".inspect, last_response.body

      get "/foo/read_raw_cookie"
      assert_equal "encrypted cookie", encryptor.decrypt_and_verify(last_response.body)
    end
  end
end
