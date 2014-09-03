require 'active_job/arguments'

module ActiveJob
  module Enqueuing
    extend ActiveSupport::Concern

    module ClassMethods
      # Push a job onto the queue.  The arguments must be legal JSON types
      # (string, int, float, nil, true, false, hash or array) or
      # GlobalID::Identification instances.  Arbitrary Ruby objects
      # are not supported.
      #
      # Returns an instance of the job class queued with args available in
      # Job#arguments.
      def perform_later(*args)
        job_or_instantiate(*args).enqueue
      end

      protected
        def job_or_instantiate(*args)
          args.first.is_a?(self) ? args.first : new(*args)
        end
    end

    # Reschedule the job to be re-executed. This is usefull in combination
    # with the +rescue_from+ option. When you rescue an exception from your job
    # you can ask Active Job to retry performing your job.
    #
    # ==== Options
    # * <tt>:in</tt> - Enqueues the job with the specified delay
    # * <tt>:at</tt> - Enqueues the job at the time specified
    # * <tt>:queue</tt> - Enqueues the job on the specified queue
    #
    # ==== Examples
    #
    #  class SiteScrapperJob < ActiveJob::Base
    #    rescue_from(ErrorLoadingSite) do
    #      retry_job queue: :low_priority
    #    end
    #    def perform(*args)
    #      # raise ErrorLoadingSite if cannot scrape
    #    end
    #  end
    def retry_job(options={})
      enqueue options
    end

    # Equeue the job to be performed by the queue adapter.
    #
    # ==== Options
    # * <tt>:in</tt> - Enqueues the job with the specified delay
    # * <tt>:at</tt> - Enqueues the job at the time specified
    # * <tt>:queue</tt> - Enqueues the job on the specified queue
    #
    # ==== Examples
    #
    #    my_job_instance.enqueue
    #    my_job_instance.enqueue in: 5.minutes
    #    my_job_instance.enqueue queue: :important
    #    my_job_instance.enqueue at: Date.tomorrow.midnight
    def enqueue(options={})
      self.scheduled_at = options[:in].seconds.from_now.to_f if options[:in]
      self.scheduled_at = options[:at].to_f if options[:at]
      self.queue_name   = self.class.queue_name_from_part(options[:queue]) if options[:queue]
      run_callbacks :enqueue do
        if self.scheduled_at
          self.class.queue_adapter.enqueue_at self, self.scheduled_at
        else
          self.class.queue_adapter.enqueue self
        end
      end
      self
    end
  end
end
