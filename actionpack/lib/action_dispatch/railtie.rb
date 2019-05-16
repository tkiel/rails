# frozen_string_literal: true

require "action_dispatch"
require "active_support/messages/rotation_configuration"

module ActionDispatch
  class Railtie < Rails::Railtie # :nodoc:
    config.action_dispatch = ActiveSupport::OrderedOptions.new
    config.action_dispatch.x_sendfile_header = nil
    config.action_dispatch.ip_spoofing_check = true
    config.action_dispatch.show_exceptions = true
    config.action_dispatch.tld_length = 1
    config.action_dispatch.ignore_accept_header = false
    config.action_dispatch.rescue_templates = {}
    config.action_dispatch.rescue_responses = {}
    config.action_dispatch.default_charset = nil
    config.action_dispatch.rack_cache = false
    config.action_dispatch.http_auth_salt = "http authentication"
    config.action_dispatch.signed_cookie_salt = "signed cookie"
    config.action_dispatch.encrypted_cookie_salt = "encrypted cookie"
    config.action_dispatch.encrypted_signed_cookie_salt = "signed encrypted cookie"
    config.action_dispatch.authenticated_encrypted_cookie_salt = "authenticated encrypted cookie"
    config.action_dispatch.use_authenticated_cookie_encryption = false
    config.action_dispatch.use_cookies_with_metadata = false
    config.action_dispatch.perform_deep_munge = true

    config.action_dispatch.default_headers = {
      "X-Frame-Options" => "SAMEORIGIN",
      "X-XSS-Protection" => "1; mode=block",
      "X-Content-Type-Options" => "nosniff",
      "X-Download-Options" => "noopen",
      "X-Permitted-Cross-Domain-Policies" => "none",
      "Referrer-Policy" => "strict-origin-when-cross-origin"
    }

    config.action_dispatch.cookies_rotations = ActiveSupport::Messages::RotationConfiguration.new

    config.eager_load_namespaces << ActionDispatch

    initializer "action_dispatch.configure" do |app|
      ActionDispatch::Http::URL.tld_length = app.config.action_dispatch.tld_length
      ActionDispatch::Request.ignore_accept_header = app.config.action_dispatch.ignore_accept_header
      ActionDispatch::Request::Utils.perform_deep_munge = app.config.action_dispatch.perform_deep_munge
      ActionDispatch::Response.default_charset = app.config.action_dispatch.default_charset || app.config.encoding
      ActionDispatch::Response.default_headers = app.config.action_dispatch.default_headers

      ActionDispatch::ExceptionWrapper.rescue_responses.merge!(config.action_dispatch.rescue_responses)
      ActionDispatch::ExceptionWrapper.rescue_templates.merge!(config.action_dispatch.rescue_templates)

      config.action_dispatch.always_write_cookie = Rails.env.development? if config.action_dispatch.always_write_cookie.nil?
      ActionDispatch::Cookies::CookieJar.always_write_cookie = config.action_dispatch.always_write_cookie

      ActionDispatch.test_app = app
    end

    initializer "action_dispatch.system_tests" do |app|
      ActiveSupport.on_load(:action_dispatch_system_test_case) do
        include app.routes.url_helpers
      end
    end
  end
end
