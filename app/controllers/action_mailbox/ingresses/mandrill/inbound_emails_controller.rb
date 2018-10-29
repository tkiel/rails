class ActionMailbox::Ingresses::Mandrill::InboundEmailsController < ActionMailbox::BaseController
  before_action :ensure_authenticated

  def create
    raw_emails.each { |raw_email| ActionMailbox::InboundEmail.create_and_extract_message_id! raw_email }
    head :ok
  rescue JSON::ParserError => error
    logger.error error.message
    head :unprocessable_entity
  end

  private
    def raw_emails
      events.select { |event| event["event"] == "inbound" }.collect { |event| event.dig("msg", "raw_msg") }
    end

    def events
      JSON.parse params.require(:mandrill_events)
    end


    def ensure_authenticated
      head :unauthorized unless authenticated?
    end

    def authenticated?
      Authenticator.new(request).authenticated?
    end

    class Authenticator
      cattr_accessor :key
      attr_reader :request

      def initialize(request)
        @request = request

        ensure_presence_of_key
      end

      def authenticated?
        ActiveSupport::SecurityUtils.secure_compare given_signature, expected_signature
      end

      private
        def ensure_presence_of_key
          unless key.present?
            raise ArgumentError, "Missing required Mandrill API key"
          end
        end


        def given_signature
          request.headers["X-Mandrill-Signature"]
        end

        def expected_signature
          Base64.strict_encode64 OpenSSL::HMAC.digest(OpenSSL::Digest::SHA1.new, key, message)
        end

        def message
          request.url + request.POST.sort.flatten.join
        end
    end
end
