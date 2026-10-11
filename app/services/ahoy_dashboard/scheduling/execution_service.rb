# frozen_string_literal: true

module AhoyDashboard

  module Scheduling

    class ExecutionService
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
        if job.enqueued_at.nil?
          claimed = ClaimService.call(key: key, token: job.job_id, now: Time.current)
          return if !claimed
        end
        return if !owned.exists?

        executing = true
        entry = JobRunEntry.open(key)
        result = yield
        finish(status: :ok)
        entry.finish! if entry
        result
      rescue StandardError => error
        finish(status: :failed, error: error) if executing
        entry.fail!(error) if entry
        raise
      ensure
        JobRunEntry.prune(key) if entry
      end

      private

      attr_reader :job

      def key
        job.class.schedule_key
      end

      def owned
        JobRun.where(key: key, claim_token: job.job_id)
      end

      def finish(status:, error: nil)
        now = Time.current
        owned.update_all(status: JobRun.statuses.fetch(status.to_s), last_finished_at: now,
                         last_error: error && "#{error.class}: #{error.message}".first(255),
                         claim_token: nil, claim_expires_at: nil, updated_at: now)
      end
    end
  end
end
