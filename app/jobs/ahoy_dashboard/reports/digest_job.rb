module AhoyDashboard
  module Reports
    class DigestJob < AhoyDashboard::Job
      class DeliveryError < StandardError; end

      queue_as :low

      self.schedule_key = "report_digest"

      def perform
        failures = Digests.periods.map do |period|
          events = Digests::SendCommand.call(period: period) do
            on(:sent) { |digest| Rails.logger.info "traffic email sent, #{digest.period} from #{digest.starts_on}" }
            on(:already_done) { |digest| Rails.logger.info "traffic email already sent, #{digest.period} from #{digest.starts_on}" }
            on(:busy) { |digest| Rails.logger.info "traffic email already going out, #{digest.period} from #{digest.starts_on}" }
            on(:disabled) { Rails.logger.info "traffic email skipped, switched off" }
          end

          events[:failed]&.yield_self { |(digest, error)| "#{digest.period}: #{error.class}: #{error.message}" }
        end.select { |value| value }

        raise DeliveryError, failures.join("; ") if failures.any?
      end
    end
  end
end
