# frozen_string_literal: true

Rails.application.routes.draw do
  scope "/rails/action_mailbox", module: "action_mailbox/ingresses" do
    post "/amazon/inbound_emails"   => "amazon/inbound_emails#create",   as: :rails_amazon_inbound_emails
    post "/mandrill/inbound_emails" => "mandrill/inbound_emails#create", as: :rails_mandrill_inbound_emails
    post "/postfix/inbound_emails"  => "postfix/inbound_emails#create",  as: :rails_postfix_inbound_emails
    post "/sendgrid/inbound_emails" => "sendgrid/inbound_emails#create", as: :rails_sendgrid_inbound_emails

    # Mailgun requires that a webhook's URL end in 'mime' for it to receive the raw contents of emails.
    post "/mailgun/inbound_emails/mime" => "mailgun/inbound_emails#create", as: :rails_mailgun_inbound_emails
  end

  # TODO: Should these be mounted within the engine only?
  scope "rails/conductor/action_mailbox/", module: "rails/conductor/action_mailbox" do
    resources :inbound_emails, as: :rails_conductor_inbound_emails do
      post "reroute" => "reroutes#create"
    end
  end
end
