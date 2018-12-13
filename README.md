# Action Mailbox

Action Mailbox routes incoming emails to controller-like mailboxes for further and encapsulated processing in Rails. 

It ships with ingress handling for AWS SNS, Mailgun, Madrill, and Sendgrid. You can also handle inbound mails directly via the Postfix ingress task/controller combination.

The inbound emails are turned into `InboundEmail` records using Active Record and feature lifecycle tracking, storage of the original email on cloud storage via Active Storage, and responsible data handling with on-by-default incineration.

These inbound emails are routed asynchronously using Active Job to one or several dedicated mailboxes, which are capable of interacting directly with the rest of your domain model.


## How does this compare to Action Mailer's inbound processing?

Rails has long had an anemic way of [receiving emails using Action Mailer](https://guides.rubyonrails.org/action_mailer_basics.html#receiving-emails), but it was poorly flushed out, lacked cohesion with the task of sending emails, and offered no help on integrating with popular inbound email processing platforms. Action Mailbox supersedes the receiving part of Action Mailer, which will be deprecated in due course.


## Installing

Assumes a Rails 5.2+ application:

1. Install the gem:

    ```ruby
    # Gemfile
    gem "actionmailbox", github: "rails/actionmailbox", require: "action_mailbox"
    ```
   
1. Install migrations needed for InboundEmail (and ensure Active Storage is setup)

   ```
   ./bin/rails action_mailbox:install
   ./bin/rails db:migrate
   ```

## Configure ingress path and password

TODO

## Examples

Configure basic routing:

```ruby
# app/models/message.rb
class ApplicationMailbox < ActionMailbox::Base
  routing /^save@/i     => :forwards
  routing /@replies\./i => :replies
end
```

Then setup a mailbox:

```ruby
# app/mailboxes/forwards_mailbox.rb
class ForwardsMailbox < ApplicationMailbox
  # Callbacks specify prerequisites to processing
  before_processing :require_forward

  def process
    if forwarder.buckets.one?
      record_forward
    else
      stage_forward_and_request_more_details
    end
  end

  private
    def require_forward
      unless message.forward?
        # Use Action Mailers to bounce incoming emails back to sender – this halts processing
        bounce_with Forwards::BounceMailer.missing_forward(
          inbound_email, forwarder: forwarder
        )
      end
    end

    def forwarder
      @forwarder ||= Person.where(email_address: mail.from)
    end

    def record_forward
      forwarder.buckets.first.record \
        Forward.new forwarder: forwarder, subject: message.subject, content: mail.content
    end

    def stage_forward_and_request_more_details
      Forwards::RoutingMailer.choose_project(mail).deliver_now
    end
end
```

## Incineration of InboundEmails

By default, an InboundEmail that has been marked as successfully processed will be incinerated after 30 days. This ensures you're not holding on to people's data willy-nilly after they may have canceled their accounts or deleted their content. The intention is that after you've processed an email, you should have extracted all the data you needed and turned it into domain models and content on your side of the application. The InboundEmail simply stays in the system for the extra time to provide debugging and forensics options.

The actual incineration is done via the `IncinerationJob` that's scheduled to run after `config.action_mailbox.incinerate_after` time. This value is by default set to `30.days`, but you can change it in your production.rb configuration. (Note that this far-future incineration scheduling relies on your job queue being able to hold jobs for that long.)


## Create incoming email through a conductor module in development

It's helpful to be able to test incoming emails in development without actually sending and receiving real emails. To accomplish this, there's a conductor controller mounted at `/rails/conductor/action_mailbox/inbound_emails`, which gives you an index of all the InboundEmails in the system, their state of processing, and a form to create a new InboundEmail as well.


## Testing mailboxes

TODO


## Development road map

Action Mailbox is destined for inclusion in Rails 6, which is due to be released some time in 2019. We will refine the framework in this separate rails/actionmailbox repository until we're ready to promote it via a pull request to rails/rails.

## License

Action Mailbox is released under the [MIT License](https://opensource.org/licenses/MIT).