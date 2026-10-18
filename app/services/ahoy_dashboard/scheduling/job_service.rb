# frozen_string_literal: true

module AhoyDashboard
  module Scheduling
    class JobService
      ERROR_LENGTH = 255

      class << self
        def call(job:, &block)
          new(job: job).call(&block)
        end
      end

      def initialize(job:)
        @job = job
      end

      private

      attr_reader :job

      def tracked?
        key.present? && JobRun.table_exists?
      end

      def key
        job.class.schedule_key
      end

      def owned
        JobRun.where(key: key, claim_token: job.job_id)
      end

      def failure(error)
        "#{error.class}: #{error.message}".first(ERROR_LENGTH)
      end
    end
  end
end
