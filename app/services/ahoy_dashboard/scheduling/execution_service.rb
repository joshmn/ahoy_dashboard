# frozen_string_literal: true

module AhoyDashboard

  module Scheduling

    class ExecutionService < JobService
      def call
        return yield unless tracked?
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

      def finish(status:, error: nil)
        now = Time.current
        owned.update_all(status: JobRun.statuses.fetch(status.to_s), last_finished_at: now,
                         last_error: error && failure(error),
                         claim_token: nil, claim_expires_at: nil, updated_at: now)
      end
    end
  end
end
