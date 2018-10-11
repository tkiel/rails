# frozen_string_literal: true

Rails.application.routes.draw do
  scope "/rails/action_mailbox" do
    post "/amazon/inbound_emails"   => "action_mailbox/ingresses/amazon/inbound_emails#create",   as: :rails_amazon_inbound_emails
    post "/postfix/inbound_emails"  => "action_mailbox/ingresses/postfix/inbound_emails#create",  as: :rails_postfix_inbound_emails
    post "/sendgrid/inbound_emails" => "action_mailbox/ingresses/sendgrid/inbound_emails#create", as: :rails_sendgrid_inbound_emails

    # Mailgun requires that the webhook's URL end in 'mime' for it to receive the raw contents of emails.
    post "/mailgun/inbound_emails/mime" => "action_mailbox/ingresses/mailgun/inbound_emails#create", as: :rails_mailgun_inbound_emails
  end

  # TODO: Should these be mounted within the engine only?
  scope "rails/conductor/action_mailbox/", module: "rails/conductor/action_mailbox" do
    resources :inbound_emails, as: :rails_conductor_inbound_emails
    post ":inbound_email_id/reroute" => "reroutes#create", as: :rails_conductor_inbound_email_reroute
  end
end
