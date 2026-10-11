# frozen_string_literal: true

module AhoyDashboard

  module Scheduling

    class EnqueueService
      class << self
        def call(job:, &block)
          new(job: job).call(&block)
        end
      end

      def initialize(job:)
        @job = job
      end

      def call
        return yield if key.blank? || !JobRun.table_exists?
        return yield if job.executions.to_i.positive? && owned.exists?

        previous = ClaimService.call(key: key, token: job.job_id,
                                     now: job.dashboard_due_at || Time.current,
                                     scheduled: job.dashboard_due_at.present?)
        return false if !previous

        result = yield
        raise job.enqueue_error if job.respond_to?(:enqueue_error) && job.enqueue_error

        result
      rescue StandardError => error
        if previous
          owned.update_all(previous.merge(status: JobRun.statuses[:failed], claim_token: nil,
                                          claim_expires_at: nil, updated_at: Time.current,
                                          last_error: "#{error.class}: #{error.message}".first(255)))
        end
        raise
      end

      private

      attr_reader :job

      def key
        job.class.schedule_key
      end

      def owned
        JobRun.where(key: key, claim_token: job.job_id)
      end
    end
  end
end
