module AhoyDashboard
  module SearchConsole
    class BackfillCommand < AhoyDashboard::Command
      Result = Data.define(:dates, :rows, :keywords, :totals, :remaining) do
        def more?
          remaining.positive?
        end
      end

      def initialize(account: nil, days: SearchConsole::BACKFILL_DAYS, now: Time.current)
        @account = account
        @days = days.to_i.clamp(1, 90)
        @now = now
      end

      def call
        return broadcast(:skipped, "search console is not configured") unless SearchConsole.enabled?
        return broadcast(:skipped, "google is not connected") unless account&.ready?
        return broadcast(:done, cursor) if slice.empty?

        @inferred_cursor = account.backfilled_to.nil?
        account.update_columns(backfilled_to: cursor) if @inferred_cursor
        events = IngestCommand.call(account: account, dates: slice, stamp: false)
        return relay(events) unless events.key?(:ok)

        advance!
        broadcast(:ok, result(events[:ok]))
      end

      private

      attr_reader :days, :now

      def account
        @account ||= GoogleAccount.current
      end

      def slice
        @slice ||= begin
          last = cursor - 1.day
          first = [ last - (days - 1).days, floor ].max

          first > last ? [] : (first..last).to_a
        end
      end

      def cursor
        @cursor ||= account.backfilled_to ||
                    SearchConsoleDay.minimum(:date) ||
                    SearchConsole.ingest_dates(now: now).first
      end

      def floor
        @floor ||= SearchConsole.earliest_available_date(now: now)
      end

      def advance!
        account.update_columns(backfilled_to: slice.first)
      end

      def result(ingested)
        Result.new(
          dates: slice,
          rows: ingested.rows,
          keywords: ingested.keywords,
          totals: ingested.totals,
          remaining: [ (slice.first - floor).to_i, 0 ].max
        )
      end

      def relay(events)
        if @inferred_cursor && !SearchConsoleDay.in_range(slice.first..slice.last).exists?
          account.update_columns(backfilled_to: nil)
        end
        key = events.keys.first

        broadcast(key, events[key])
      end
    end
  end
end
