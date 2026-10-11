module AhoyDashboard
  module Alerts
    class RunJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "alerts"

      def perform
        RunCommand.call do
          on(:ok) { |outcome| Rails.logger.info "alerts fired #{outcome.fired.size}, delivered #{outcome.delivered}, #{outcome.repeats} already said" }
          on(:disabled) { Rails.logger.info "alerts skipped, switched off" }
          on(:nothing_on) { Rails.logger.info "alerts skipped, no rule is switched on" }
        end
      end
    end
  end
end
