require 'delegate'

module ActionMailer
  class MessageDelivery < Delegator
    def initialize(mailer, mail_method, *args)
      @mailer = mailer
      @mail_method = mail_method
      @args = args
    end

    def __getobj__
      @obj ||= @mailer.send(:new, @mail_method, *@args).message
    end

    def __setobj__(obj)
      @obj = obj
    end

    def message #:nodoc:
      __getobj__
    end

    def deliver_later!(options={})
      enqueue_delivery :deliver_now!, options
    end

    def deliver_later(options={})
      enqueue_delivery :deliver_now, options
    end

    def deliver_now!
      message.deliver!
    end

    def deliver_now
      message.deliver
    end

    def deliver!
      ActiveSupport::Deprecation.warn "#deliver! is deprecated and will be removed on Rails 5. " \
        "Use #deliver_now! to deliver immediately or #deliver_later! to deliver through ActiveJob"
      deliver_now!
    end

    def deliver
      ActiveSupport::Deprecation.warn "#deliver is deprecated and will be removed on Rails 5. " \
        "Use #deliver_now to deliver immediately or #deliver_later to deliver through ActiveJob"
      deliver_now
    end

    private
    def enqueue_delivery(delivery_method, options={})
      args = @mailer.name, @mail_method.to_s, delivery_method.to_s, *@args
      enqueue_method = :enqueue
      if options[:at]
        enqueue_method = :enqueue_at
        args.unshift options[:at]
      elsif options[:in]
        enqueue_method = :enqueue_in
        args.unshift options[:in]
      end
      ActionMailer::DeliveryJob.send enqueue_method, *args
    end
  end
end
