module AhoyDashboard
  module SearchConsole
    class BackfillJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "search_console_backfill"

      def perform
        BackfillCommand.call do
          on(:ok) do |result|
            Rails.logger.info "search console backfill wrote #{result.keywords} keyword rows over " \
                              "#{result.dates.first} to #{result.dates.last}, #{result.remaining} days left"
          end
          on(:done) { |date| Rails.logger.info "search console backfill has reached #{date}, nothing left to pull" }
          on(:skipped) { |reason| Rails.logger.info "search console backfill skipped: #{reason}" }
          on(:rate_limited) { |message| Rails.logger.warn "search console backfill hit a quota: #{message}" }
          on(:failed) do |message|
            Rails.logger.warn "search console backfill failed: #{message}"
            raise Failed, message
          end
        end
      end
    end
  end
end
