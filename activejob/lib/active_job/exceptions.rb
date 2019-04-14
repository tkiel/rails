# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module ActiveJob
  # Provides behavior for retrying and discarding jobs on exceptions.
  module Exceptions
    extend ActiveSupport::Concern

    module ClassMethods
      # Catch the exception and reschedule job for re-execution after so many seconds, for a specific number of attempts.
      # If the exception keeps getting raised beyond the specified number of attempts, the exception is allowed to
      # bubble up to the underlying queuing system, which may have its own retry mechanism or place it in a
      # holding queue for inspection.
      #
      # You can also pass a block that'll be invoked if the retry attempts fail for custom logic rather than letting
      # the exception bubble up. This block is yielded with the job instance as the first and the error instance as the second parameter.
      #
      # ==== Options
      # * <tt>:wait</tt> - Re-enqueues the job with a delay specified either in seconds (default: 3 seconds),
      #   as a computing proc that the number of executions so far as an argument, or as a symbol reference of
      #   <tt>:exponentially_longer</tt>, which applies the wait algorithm of <tt>(executions ** 4) + 2</tt>
      #   (first wait 3s, then 18s, then 83s, etc)
      # * <tt>:attempts</tt> - Re-enqueues the job the specified number of times (default: 5 attempts)
      # * <tt>:queue</tt> - Re-enqueues the job on a different queue
      # * <tt>:priority</tt> - Re-enqueues the job with a different priority
      #
      # ==== Examples
      #
      #  class RemoteServiceJob < ActiveJob::Base
      #    retry_on CustomAppException # defaults to 3s wait, 5 attempts
      #    retry_on AnotherCustomAppException, wait: ->(executions) { executions * 2 }
      #
      #    retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
      #    retry_on Net::OpenTimeout, Timeout::Error, wait: :exponentially_longer, attempts: 10 # retries at most 10 times for Net::OpenTimeout and Timeout::Error combined
      #    # To retry at most 10 times for each individual exception:
      #    # retry_on Net::OpenTimeout, wait: :exponentially_longer, attempts: 10
      #    # retry_on Timeout::Error, wait: :exponentially_longer, attempts: 10
      #
      #    retry_on(YetAnotherCustomAppException) do |job, error|
      #      ExceptionNotifier.caught(error)
      #    end
      #
      #    def perform(*args)
      #      # Might raise CustomAppException, AnotherCustomAppException, or YetAnotherCustomAppException for something domain specific
      #      # Might raise ActiveRecord::Deadlocked when a local db deadlock is detected
      #      # Might raise Net::OpenTimeout or Timeout::Error when the remote service is down
      #    end
      #  end
      def retry_on(*exceptions, wait: 3.seconds, attempts: 5, queue: nil, priority: nil)
        rescue_from(*exceptions) do |error|
          # Guard against jobs that were persisted before we started having individual executions counters per retry_on
          self.exception_executions ||= {}
          self.exception_executions[exceptions.to_s] = (exception_executions[exceptions.to_s] || 0) + 1

          if exception_executions[exceptions.to_s] < attempts
            retry_job wait: determine_delay(seconds_or_duration_or_algorithm: wait, executions: exception_executions[exceptions.to_s]), queue: queue, priority: priority, error: error
          else
            if block_given?
              instrument :retry_stopped, error: error do
                yield self, error
              end
            else
              instrument :retry_stopped, error: error
              raise error
            end
          end
        end
      end

      # Discard the job with no attempts to retry, if the exception is raised. This is useful when the subject of the job,
      # like an Active Record, is no longer available, and the job is thus no longer relevant.
      #
      # You can also pass a block that'll be invoked. This block is yielded with the job instance as the first and the error instance as the second parameter.
      #
      # ==== Example
      #
      #  class SearchIndexingJob < ActiveJob::Base
      #    discard_on ActiveJob::DeserializationError
      #    discard_on(CustomAppException) do |job, error|
      #      ExceptionNotifier.caught(error)
      #    end
      #
      #    def perform(record)
      #      # Will raise ActiveJob::DeserializationError if the record can't be deserialized
      #      # Might raise CustomAppException for something domain specific
      #    end
      #  end
      def discard_on(*exceptions)
        rescue_from(*exceptions) do |error|
          instrument :discard, error: error do
            yield self, error if block_given?
          end
        end
      end
    end

    # Reschedules the job to be re-executed. This is useful in combination
    # with the +rescue_from+ option. When you rescue an exception from your job
    # you can ask Active Job to retry performing your job.
    #
    # ==== Options
    # * <tt>:wait</tt> - Enqueues the job with the specified delay in seconds
    # * <tt>:wait_until</tt> - Enqueues the job at the time specified
    # * <tt>:queue</tt> - Enqueues the job on the specified queue
    # * <tt>:priority</tt> - Enqueues the job with the specified priority
    #
    # ==== Examples
    #
    #  class SiteScraperJob < ActiveJob::Base
    #    rescue_from(ErrorLoadingSite) do
    #      retry_job queue: :low_priority
    #    end
    #
    #    def perform(*args)
    #      # raise ErrorLoadingSite if cannot scrape
    #    end
    #  end
    def retry_job(options = {})
      instrument :enqueue_retry, options.slice(:error, :wait) do
        enqueue options
      end
    end

    private
      def determine_delay(seconds_or_duration_or_algorithm:, executions:)
        case seconds_or_duration_or_algorithm
        when :exponentially_longer
          (executions**4) + 2
        when ActiveSupport::Duration
          duration = seconds_or_duration_or_algorithm
          duration.to_i
        when Integer
          seconds = seconds_or_duration_or_algorithm
          seconds
        when Proc
          algorithm = seconds_or_duration_or_algorithm
          algorithm.call(executions)
        else
          raise "Couldn't determine a delay based on #{seconds_or_duration_or_algorithm.inspect}"
        end
      end

      def instrument(name, error: nil, wait: nil, &block)
        payload = { job: self, adapter: self.class.queue_adapter, error: error, wait: wait }

        ActiveSupport::Notifications.instrument("#{name}.active_job", payload, &block)
      end
  end
end
