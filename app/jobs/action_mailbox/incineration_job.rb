class ActionMailbox::IncinerationJob < ApplicationJob
  queue_as :action_mailbox_incineration

  def self.schedule(inbound_email)
    set(wait: ActionMailbox.incinerate_after).perform_later(inbound_email)
  end

  def perform(inbound_email)
    inbound_email.incinerate
  end
end
