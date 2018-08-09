# frozen_string_literal: true

module ActiveJob
  module QueueAdapters
    # == Test adapter for Active Job
    #
    # The test adapter should be used only in testing. Along with
    # <tt>ActiveJob::TestCase</tt> and <tt>ActiveJob::TestHelper</tt>
    # it makes a great tool to test your Rails application.
    #
    # To use the test adapter set queue_adapter config to +:test+.
    #
    #   Rails.application.config.active_job.queue_adapter = :test
    class TestAdapter
      attr_accessor(:perform_enqueued_jobs, :perform_enqueued_at_jobs, :filter, :reject)
      attr_writer(:enqueued_jobs, :performed_jobs)

      # Provides a store of all the enqueued jobs with the TestAdapter so you can check them.
      def enqueued_jobs
        @enqueued_jobs ||= []
      end

      # Provides a store of all the performed jobs with the TestAdapter so you can check them.
      def performed_jobs
        @performed_jobs ||= []
      end

      def enqueue(job) #:nodoc:
        return if filtered?(job)

        job_data = job_to_hash(job)
        perform_or_enqueue(perform_enqueued_jobs, job, job_data)
      end

      def enqueue_at(job, timestamp) #:nodoc:
        return if filtered?(job)

        job_data = job_to_hash(job, at: timestamp)
        perform_or_enqueue(perform_enqueued_at_jobs, job, job_data)
      end

      private
        def job_to_hash(job, extras = {})
          { job: job.class, args: job.serialize.fetch("arguments"), queue: job.queue_name }.merge!(extras)
        end

        def perform_or_enqueue(perform, job, job_data)
          if perform
            performed_jobs << job_data
            Base.execute job.serialize
          else
            enqueued_jobs << job_data
          end
        end

        def filtered?(job)
          if filter
            !Array(filter).include?(job.class)
          elsif reject
            Array(reject).include?(job.class)
          else
            false
          end
        end
    end
  end
end
