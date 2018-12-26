# frozen_string_literal: true

# The base class for all Active Mailbox ingress controllers.
class ActionMailbox::BaseController < ActionController::Base
  skip_forgery_protection

  before_action :ensure_configured

  def self.prepare
    # Override in concrete controllers to run code on load.
  end

  private
    def ensure_configured
      unless ActionMailbox.ingress == ingress_name
        head :not_found
      end
    end

    def ingress_name
      self.class.name.remove(/\AActionMailbox::Ingresses::/, /::InboundEmailsController\z/).underscore.to_sym
    end


    def authenticate_by_password
      if password.present?
        http_basic_authenticate_or_request_with name: "actionmailbox", password: password, realm: "Action Mailbox"
      else
        raise ArgumentError, "Missing required ingress credentials"
      end
    end

    def password
      Rails.application.credentials.dig(:action_mailbox, :ingress_password) || ENV["RAILS_INBOUND_EMAIL_PASSWORD"]
    end
end
