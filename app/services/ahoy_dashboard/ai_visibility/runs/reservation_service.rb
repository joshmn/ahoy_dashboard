# frozen_string_literal: true

module AhoyDashboard

  module AiVisibility

    module Runs

      class ReservationService
        LOCK_NAMESPACE = 1_684_370_241
        LOCK_KEY = 1

        class << self
          def call(**options)
            new(**options).call
          end
        end

        def initialize(prompts:, targets:, trigger:, now:)
          @prompts = prompts
          @targets = targets
          @trigger = trigger
          @now = now
        end

        def call
          Run.transaction do
            Run.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{LOCK_KEY})")
            remaining = AiVisibility.remaining(now: now)
            next skipped(remaining: remaining) if requests > remaining

            run = Run.create!(status: :queued, trigger: trigger, requests: requests, started_at: now)
            Answer.insert_all!(reservations(run: run))
            run
          end
        end

        private

        attr_reader :prompts, :targets, :trigger, :now

        def requests
          prompts.size * targets.size
        end

        def skipped(remaining:)
          Run.create!(status: :skipped, trigger: trigger, requests: requests, started_at: now,
                      skip_reason: "A run needs #{requests} requests and #{remaining} are left this month.")
        end

        def reservations(run:)
          prompts.flat_map do |prompt|
            targets.map do |target|
              { run_id: run.id, prompt_id: prompt.id, assistant: target.assistant, model: target.model,
                status: "pending", asked_at: now, created_at: now, updated_at: now }
            end
          end
        end
      end
    end
  end
end
