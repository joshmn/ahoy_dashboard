module AhoyDashboard
  module SearchConsole
    # Hourly, and does nothing at all once the history is filled in. It takes a
    # month a run, so a fresh connection has its sixteen months inside a day and
    # then this is a no-op forever, which is the point: nobody has to remember to
    # run anything.
    #
    # Its own schedule rather than a step at the end of the nightly ingest, so a
    # slow walk through old data can never delay or fail the fresh window, which
    # is the half that matters.
    class BackfillJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "search_console_backfill"

      def perform
        return unless SearchConsole.enabled?

        account = GoogleAccount.current
        return unless account&.ready?

        BackfillCommand.call(account: account) do
          on(:ok) do |result|
            Rails.logger.info "search console backfill wrote #{result.keywords} keyword rows over " \
                              "#{result.dates.first} to #{result.dates.last}, #{result.remaining} days left"
          end
          on(:done) { |date| Rails.logger.info "search console backfill has reached #{date}, nothing left to pull" }
          on(:skipped) { |reason| Rails.logger.info "search console backfill skipped: #{reason}" }
          on(:rate_limited) { |message| Rails.logger.warn "search console backfill hit a quota: #{message}" }
          on(:failed) { |message| Rails.logger.warn "search console backfill failed: #{message}" }
        end
      end
    end
  end
end
