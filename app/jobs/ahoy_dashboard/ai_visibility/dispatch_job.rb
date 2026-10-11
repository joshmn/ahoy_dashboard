module AhoyDashboard
  module AiVisibility
    class DispatchJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "ai_visibility"

      def perform(now: Time.current)
        return unless AiVisibility.ready?

        Runs::RecoverCommand.call(now: now)
        return unless AiVisibility.due?(now: now)

        Runs::StartCommand.call(trigger: :schedule, now: now) do
          on(:ok) { |run| Rails.logger.info "ai visibility run #{run.id} started, #{run.requests} requests" }
          on(:over_cap) { |run| Rails.logger.warn "ai visibility run skipped: #{run.skip_reason}" }
        end
      end
    end
  end
end
