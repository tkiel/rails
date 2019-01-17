# frozen_string_literal: true

require "active_support/core_ext/hash/keys"
require "action_dispatch/middleware/session/abstract_store"
require "rack/session/cookie"

module ActionDispatch
  module Session
    # This cookie-based session store is the Rails default. It is
    # dramatically faster than the alternatives.
    #
    # Sessions typically contain at most a user_id and flash message; both fit
    # within the 4K cookie size limit. A CookieOverflow exception is raised if
    # you attempt to store more than 4K of data.
    #
    # The cookie jar used for storage is automatically configured to be the
    # best possible option given your application's configuration.
    #
    # Your cookies will be encrypted using your apps secret_key_base. This
    # goes a step further than signed cookies in that encrypted cookies cannot
    # be altered or read by users. This is the default starting in Rails 4.
    #
    # Configure your session store in an initializer:
    #
    #   Rails.application.config.session_store :cookie_store, key: '_your_app_session'
    #
    # By default, your secret key base is derived from your application name in
    # the test and development environments. In all other environments, it is stored
    # encrypted in the <tt>config/credentials.yml.enc</tt> file.
    #
    # If your application was not updated to Rails 5.2 defaults, the secret_key_base
    # will be found in the old <tt>config/secrets.yml</tt> file.
    #
    # Note that changing your secret_key_base will invalidate all existing session.
    # Additionally, you should take care to make sure you are not relying on the
    # ability to decode signed cookies generated by your app in external
    # applications or JavaScript before changing it.
    #
    # Because CookieStore extends Rack::Session::Abstract::Persisted, many of the
    # options described there can be used to customize the session cookie that
    # is generated. For example:
    #
    #   Rails.application.config.session_store :cookie_store, expire_after: 14.days
    #
    # would set the session cookie to expire automatically 14 days after creation.
    # Other useful options include <tt>:key</tt>, <tt>:secure</tt> and
    # <tt>:httponly</tt>.
    class CookieStore < AbstractStore
      def initialize(app, options = {})
        super(app, options.merge!(cookie_only: true))
      end

      def delete_session(req, session_id, options)
        new_sid = generate_sid unless options[:drop]
        # Reset hash and Assign the new session id
        req.set_header("action_dispatch.request.unsigned_session_cookie", new_sid ? { "session_id" => new_sid } : {})
        new_sid
      end

      def load_session(req)
        stale_session_check! do
          data = unpacked_cookie_data(req)
          data = persistent_session_id!(data)
          [data["session_id"], data]
        end
      end

      private

        def extract_session_id(req)
          stale_session_check! do
            unpacked_cookie_data(req)["session_id"]
          end
        end

        def unpacked_cookie_data(req)
          req.fetch_header("action_dispatch.request.unsigned_session_cookie") do |k|
            v = stale_session_check! do
              if data = get_cookie(req)
                data.stringify_keys!
              end
              data || {}
            end
            req.set_header k, v
          end
        end

        def persistent_session_id!(data, sid = nil)
          data ||= {}
          data["session_id"] ||= sid || generate_sid
          data
        end

        def write_session(req, sid, session_data, options)
          session_data["session_id"] = sid
          session_data
        end

        def set_cookie(request, session_id, cookie)
          cookie_jar(request)[@key] = cookie
        end

        def get_cookie(req)
          cookie_jar(req)[@key]
        end

        def cookie_jar(request)
          request.cookie_jar.signed_or_encrypted
        end
    end
  end
end
