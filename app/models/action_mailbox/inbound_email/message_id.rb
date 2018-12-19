# frozen_string_literal: true

# The `Message-ID` as specified by rfc822 is supposed to be a unique identifier for that individual email. 
# That makes it an ideal tracking token for debugging and forensics, just like `X-Request-Id` does for 
# web request.
#
# If an inbound email does not, against the rfc822 mandate, specify a Message-ID, one will be generated
# using the approach from `Mail::MessageIdField`.
module ActionMailbox::InboundEmail::MessageId
  extend ActiveSupport::Concern

  included do
    before_save :generate_missing_message_id
  end

  module ClassMethods
    # Create a new `InboundEmail` from the raw `source` of the email, which be uploaded as a Active Storage
    # attachment called `raw_email`. Before the upload, extract the Message-ID from the `source` and set
    # it as an attribute on the new `InboundEmail`.
    def create_and_extract_message_id!(source, **options)
      create! message_id: extract_message_id(source), **options do |inbound_email|
        inbound_email.raw_email.attach io: StringIO.new(source), filename: "message.eml", content_type: "message/rfc822"
      end
    end

    private
      def extract_message_id(source)
        Mail.from_source(source).message_id rescue nil
      end
  end

  private
    def generate_missing_message_id
      self.message_id ||= Mail::MessageIdField.new.message_id.tap do |message_id|
        logger.warn "Message-ID couldn't be parsed or is missing. Generated a new Message-ID: #{message_id}"
      end
    end
end
