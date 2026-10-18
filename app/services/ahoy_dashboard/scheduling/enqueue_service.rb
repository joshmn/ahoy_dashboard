# frozen_string_literal: true

module AhoyDashboard

  module Scheduling

    class EnqueueService < JobService
      def call
        return yield unless tracked?
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
                                          last_error: failure(error)))
        end
        raise
      end
    end
  end
end
