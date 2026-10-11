# frozen_string_literal: true

module AhoyDashboard

  module Scheduling

    class TickService
      class << self
        def call(now:)
          new(now: now).call
        end
      end

      def initialize(now:)
        @now = now
      end

      def call
        Schedule::ALL.each { |entry| consider(entry: entry) }
        refresh_dashboard
      end

      private

      attr_reader :now

      def refresh_dashboard
        Dashboards::SnapshotEnqueueService.call
      rescue StandardError => error
        Rails.logger.warn("ahoy_dashboard tick could not refresh the dashboard: #{error.class}: #{error.message}")
      end

      def consider(entry:)
        record = JobRun.for(entry.key)
        return record.switched_off!(now) if !entry.on?

        job = entry.job_class.new
        job.dashboard_due_at = now
        job.enqueue
      rescue StandardError => error
        Rails.logger.warn "ahoy_dashboard tick could not start #{entry.key}: #{error.class}: #{error.message}"
      end
    end
  end
end
