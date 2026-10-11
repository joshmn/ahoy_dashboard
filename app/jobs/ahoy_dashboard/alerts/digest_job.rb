module AhoyDashboard
  module Alerts
    class DigestJob < AhoyDashboard::Job
      class DeliveryError < StandardError; end

      queue_as :low

      self.schedule_key = "alert_digest"

      def perform
        failures = Digests.periods.map do |period|
          events = Digests::SendCommand.call(period: period) do
            on(:sent) { |digest| Rails.logger.info "alert email sent, #{digest.period} from #{digest.starts_on}" }
            on(:skipped) { |digest| Rails.logger.info "alert email skipped, nothing fired #{digest.period} from #{digest.starts_on}" }
            on(:already_done) { |digest| Rails.logger.info "alert email already sent, #{digest.period} from #{digest.starts_on}" }
            on(:busy) { |digest| Rails.logger.info "alert email already going out, #{digest.period} from #{digest.starts_on}" }
            on(:disabled) { Rails.logger.info "alert email skipped, switched off" }
          end

          events[:failed]&.yield_self { |(digest, error)| "#{digest.period}: #{error.class}: #{error.message}" }
        end.select { |value| value }

        raise DeliveryError, failures.join("; ") if failures.any?
      end
    end
  end
end
