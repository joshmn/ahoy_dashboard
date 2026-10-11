# frozen_string_literal: true

module AhoyDashboard

  module Scheduling

    class ClaimService
      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(key:, token:, now:, scheduled: false)
        @key = key
        @token = token
        @now = now
        @scheduled = scheduled
      end

      def call
        row = JobRun.for(key)
        row.with_lock do
          return false if row.claim_expires_at && row.claim_expires_at > now

          expired = row.claim_token.present?
          return false if scheduled && !expired && !Schedule.find(key).due?(row.last_run_at, now: now)

          previous = row.attributes.slice("last_run_at", "runs_count")
          row.update!(status: :running, last_run_at: now, last_error: nil,
                      runs_count: row.runs_count + 1, claim_token: token,
                      claim_expires_at: now + JobRun::STUCK_AFTER)
          previous
        end
      end

      private

      attr_reader :key, :token, :now, :scheduled
    end
  end
end
