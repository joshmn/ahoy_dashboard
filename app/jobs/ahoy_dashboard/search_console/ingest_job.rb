module AhoyDashboard
  module SearchConsole
    class IngestJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "search_console_ingest"

      def perform
        IngestCommand.call do
          on(:ok) { |result| Rails.logger.info "search console ingest wrote #{result.rows} rows over #{result.dates.size} days" }
          on(:skipped) { |reason| Rails.logger.info "search console ingest skipped: #{reason}" }
          on(:rate_limited) { |message| Rails.logger.warn "search console ingest hit a quota: #{message}" }
          on(:failed) do |message|
            Rails.logger.warn "search console ingest failed: #{message}"
            raise Failed, message
          end
        end
      end
    end
  end
end
