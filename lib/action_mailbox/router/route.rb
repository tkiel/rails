class ActionMailbox::Router::Route
  class InvalidAddressError < StandardError; end

  attr_reader :address, :mailbox_name

  def initialize(address, to:)
    @address, @mailbox_name = address, to
  end

  def match?(inbound_email)
    case address
    when String
      recipients_from(inbound_email.mail).any? { |recipient| address.casecmp?(recipient) }
    when Regexp
      recipients_from(inbound_email.mail).any? { |recipient| address.match?(recipient) }
    when Proc
      address.call(inbound_email)
    else
      address.try(:match?, inbound_email) || raise(InvalidAddressError)
    end
  end

  def mailbox_class
    "#{mailbox_name.to_s.camelize}Mailbox".constantize
  end

  private
    def recipients_from(mail)
      Array(mail.to) + Array(mail.cc) + Array(mail.bcc)
    end
end
