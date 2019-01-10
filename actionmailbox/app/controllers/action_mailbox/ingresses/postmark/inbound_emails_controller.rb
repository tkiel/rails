# frozen_string_literal: true

module ActionMailbox
  # Ingests inbound emails from Postmark. Requires +RawEmail+ parameter containing a full RFC 822 message.
  #
  # Authenticates requests using HTTP basic access authentication. The username is always +actionmailbox+, and the
  # password is read from the application's encrypted credentials or an environment variable. See the Usage section below.
  #
  # Note that basic authentication is insecure over unencrypted HTTP. An attacker that intercepts cleartext requests to
  # the Postmark ingress can learn its password. You should only use the Postmark ingress over HTTPS.
  #
  # Returns:
  #
  # - <tt>204 No Content</tt> if an inbound email is successfully recorded and enqueued for routing to the appropriate mailbox
  # - <tt>401 Unauthorized</tt> if the request's signature could not be validated
  # - <tt>404 Not Found</tt> if Action Mailbox is not configured to accept inbound emails from Postmark
  # - <tt>422 Unprocessable Entity</tt> if the request is missing the required +RawEmail+ parameter
  # - <tt>500 Server Error</tt> if the ingress password is not configured, or if one of the Active Record database,
  #   the Active Storage service, or the Active Job backend is misconfigured or unavailable
  #
  # == Usage
  #
  # 1. Tell Action Mailbox to accept emails from Postmark:
  #
  #        # config/environments/production.rb
  #        config.action_mailbox.ingress = :postmark
  #
  # 2. Generate a strong password that Action Mailbox can use to authenticate requests to the Postmark ingress.
  #
  #    Use <tt>rails credentials:edit</tt> to add the password to your application's encrypted credentials under
  #    +action_mailbox.ingress_password+, where Action Mailbox will automatically find it:
  #
  #        action_mailbox:
  #          ingress_password: ...
  #
  #    Alternatively, provide the password in the +RAILS_INBOUND_EMAIL_PASSWORD+ environment variable.
  #
  # 3. {Configure Postmark inbound webhook}[https://postmarkapp.com/manual#configure-your-inbound-webhook-url]
  #    to forward inbound emails to +/rails/action_mailbox/postmark/inbound_emails+ with the username +actionmailbox+ and
  #    the password you previously generated. If your application lived at <tt>https://example.com</tt>, you would
  #    configure Postmark with the following fully-qualified URL:
  #
  #        https://actionmailbox:PASSWORD@example.com/rails/action_mailbox/postmark/inbound_emails
  #
  #    *NOTE:* When configuring your Postmark inbound webhook, be sure to check the box labeled *"Include raw email
  #    content in JSON payload"*. Action Mailbox needs the raw email content to work.
  class Ingresses::Postmark::InboundEmailsController < ActionMailbox::BaseController
    before_action :authenticate_by_password

    def create
      ActionMailbox::InboundEmail.create_and_extract_message_id! params.require("RawEmail")
    rescue ActionController::ParameterMissing => error
      logger.error <<~MESSAGE
        #{error.message}

        When configuring your Postmark inbound webhook, be sure to check the box
        labeled "Include raw email content in JSON payload".
      MESSAGE
      head :unprocessable_entity
    end
  end
end
