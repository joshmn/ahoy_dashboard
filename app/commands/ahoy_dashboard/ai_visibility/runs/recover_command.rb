# frozen_string_literal: true

module AhoyDashboard

  module AiVisibility

    module Runs

      class RecoverCommand < AhoyDashboard::Command
        STALE_AFTER = 6.hours
        INTERRUPTED = "The worker stopped before recording a response. This request will not be sent twice.".freeze

        def initialize(now: Time.current)
          @now = now
        end

        def call
          stale = Answer.where("updated_at < ?", now - STALE_AFTER)
          failed = stale.processing.update_all(status: "failed", error: INTERRUPTED, updated_at: now)
          stale.pending.find_each do |answer|
            Prompts::RunJob.perform_later(answer.run_id, answer.prompt_id, answer.assistant, answer.model)
          end
          broadcast(:ok, failed)
        end

        private

        attr_reader :now
      end
    end
  end
end
