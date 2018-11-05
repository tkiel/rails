require "rails/engine"

module ActionMailbox
  class Engine < Rails::Engine
    isolate_namespace ActionMailbox
    config.eager_load_namespaces << ActionMailbox

    config.action_mailbox = ActiveSupport::OrderedOptions.new
    config.action_mailbox.incinerate_after = 30.days

    initializer "action_mailbox.config" do
      config.after_initialize do |app|
        ActionMailbox.logger = app.config.action_mailbox.logger || Rails.logger
        ActionMailbox.incinerate_after = app.config.action_mailbox.incinerate_after || 30.days
      end
    end

    initializer "action_mailbox.ingress" do
      config.after_initialize do |app|
        if ActionMailbox.ingress = app.config.action_mailbox.ingress.presence
          config.to_prepare do
            if ingress_controller_class = "ActionMailbox::Ingresses::#{ActionMailbox.ingress.to_s.classify}::InboundEmailsController".safe_constantize
              ingress_controller_class.prepare
            end
          end
        end
      end
    end
  end
end
