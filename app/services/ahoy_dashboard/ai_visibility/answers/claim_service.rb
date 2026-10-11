# frozen_string_literal: true

module AhoyDashboard

  module AiVisibility

    module Answers

      class ClaimService
        class << self
          def call(**options)
            new(**options).call
          end
        end

        def initialize(run:, prompt:, assistant:, model:, now:)
          @run = run
          @prompt = prompt
          @assistant = assistant
          @model = model
          @now = now
        end

        def call
          Answer.transaction do
            Answer.connection.execute("SELECT pg_advisory_xact_lock(#{Runs::ReservationService::LOCK_NAMESPACE}, #{Runs::ReservationService::LOCK_KEY})")
            answer = reservation
            next if answer.nil? || !answer.pending?
            next if !roll_over(answer: answer)

            claimed = Answer.where(id: answer.id, status: :pending)
              .update_all(status: "processing", asked_at: now, updated_at: now)
            answer.reload if claimed == 1
          end
        end

        private

        attr_reader :run, :prompt, :assistant, :model, :now

        def roll_over(answer:)
          return true if answer.asked_at >= AiVisibility.month_start(now: now)
          return true if AiVisibility.remaining(now: now).positive?

          answer.update!(status: :failed, error: "The request expired before capacity was available this month.")
          false
        end

        def reservation
          existing = Answer.find_by(run: run, prompt: prompt, assistant: assistant, model: model)
          return existing if existing
          return if AiVisibility.remaining(now: now).zero?

          Answer.create!(run: run, prompt: prompt, assistant: assistant, model: model,
                         status: :pending, asked_at: now)
        rescue ActiveRecord::RecordNotUnique
          Answer.find_by!(run: run, prompt: prompt, assistant: assistant, model: model)
        end
      end
    end
  end
end
