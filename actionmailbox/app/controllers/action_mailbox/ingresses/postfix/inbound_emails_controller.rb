# frozen_string_literal: true

module ActionMailbox
  # Ingests inbound emails relayed from Postfix.
  #
  # Authenticates requests using HTTP basic access authentication. The username is always +actionmailbox+, and the
  # password is read from the application's encrypted credentials or an environment variable. See the Usage section below.
  #
  # Note that basic authentication is insecure over unencrypted HTTP. An attacker that intercepts cleartext requests to
  # the Postfix ingress can learn its password. You should only use the Postfix ingress over HTTPS.
  #
  # Returns:
  #
  # - <tt>204 No Content</tt> if an inbound email is successfully recorded and enqueued for routing to the appropriate mailbox
  # - <tt>401 Unauthorized</tt> if the request could not be authenticated
  # - <tt>404 Not Found</tt> if Action Mailbox is not configured to accept inbound emails from Postfix
  # - <tt>415 Unsupported Media Type</tt> if the request does not contain an RFC 822 message
  # - <tt>500 Server Error</tt> if the ingress password is not configured, or if one of the Active Record database,
  #   the Active Storage service, or the Active Job backend is misconfigured or unavailable
  #
  # == Usage
  #
  # 1. Tell Action Mailbox to accept emails from Postfix:
  #
  #        # config/environments/production.rb
  #        config.action_mailbox.ingress = :postfix
  #
  # 2. Generate a strong password that Action Mailbox can use to authenticate requests to the Postfix ingress.
  #
  #    Use <tt>rails credentials:edit</tt> to add the password to your application's encrypted credentials under
  #    +action_mailbox.ingress_password+, where Action Mailbox will automatically find it:
  #
  #        action_mailbox:
  #          ingress_password: ...
  #
  #    Alternatively, provide the password in the +RAILS_INBOUND_EMAIL_PASSWORD+ environment variable.
  #
  # 3. {Configure Postfix}{https://serverfault.com/questions/258469/how-to-configure-postfix-to-pipe-all-incoming-email-to-a-script}
  #    to pipe inbound emails to <tt>bin/rails action_mailbox:ingress:postfix</tt>, providing the +URL+ of the Postfix
  #    ingress and the +INGRESS_PASSWORD+ you previously generated.
  #
  #    If your application lived at <tt>https://example.com</tt>, the full command would look like this:
  #
  #        URL=https://example.com/rails/action_mailbox/postfix/inbound_emails INGRESS_PASSWORD=... bin/rails action_mailbox:ingress:postfix
  class Ingresses::Postfix::InboundEmailsController < ActionMailbox::BaseController
    before_action :authenticate_by_password, :require_valid_rfc822_message

    def create
      ActionMailbox::InboundEmail.create_and_extract_message_id! request.body.read
    end

    private
      def require_valid_rfc822_message
        unless request.content_type == "message/rfc822"
          head :unsupported_media_type
        end
      end
  end
end
