module AhoyDashboard
  module SearchConsole
    # One bite of history, taken behind the nightly window rather than in front
    # of it.
    #
    # IngestCommand only ever asks for the last seven finished days, so on its
    # own the record starts whenever the job first ran and a keyword trend has a
    # week on it. Google serves sixteen months and then drops a day for good, so
    # this walks backwards a month at a time until it reaches the oldest day the
    # API still answers for, and then it has nothing left to do.
    #
    # Backwards and contiguous, tracked by a single watermark on the account. The
    # scan log could answer "have I asked about this day" a day at a time now,
    # but the walk is one interval moving one way and a watermark says that in
    # one column, so there is nothing for it to gain by looking.
    #
    # The pull itself is IngestCommand with different dates. Nothing about an old
    # day is different, and having two things that write these tables would be
    # two things to keep in agreement.
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

      # The next slice down, floored at the oldest day Google will answer for. An
      # empty slice is the finish line, and it stays empty from then on because
      # the floor moves forward a day at a time and the cursor is already under
      # it.
      def slice
        @slice ||= begin
          last = cursor - 1.day
          first = [ last - (days - 1).days, floor ].max

          first > last ? [] : (first..last).to_a
        end
      end

      # Where the walk is up to. The stored watermark first; failing that the
      # oldest day already asked about, so a reconnect resumes rather than
      # re-pulling sixteen months it has; failing that the top of the nightly
      # window, which is the oldest day the ordinary run covers.
      #
      # The scan log rather than the oldest keyword row, because the oldest day
      # reached can be one Google had nothing for, and reading the rows would
      # send the walk back over everything below it again.
      def cursor
        @cursor ||= account.backfilled_to ||
                    SearchConsoleDay.minimum(:date) ||
                    SearchConsole.ingest_dates(now: now).first
      end

      def floor
        @floor ||= SearchConsole.earliest_available_date(now: now)
      end

      # Only after the days are stored. A failed slice leaves the watermark where
      # it was and the next run asks for the same days again.
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

      # IngestCommand already recorded the reason on the account and already
      # knows how to describe it, so this passes the outcome through rather than
      # writing a second, worse version of it.
      def relay(events)
        # The cursor is pinned before ingestion so an interrupted worker can
        # replay its slice. A handled failure before any write needs no marker.
        if @inferred_cursor && !SearchConsoleDay.in_range(slice.first..slice.last).exists?
          account.update_columns(backfilled_to: nil)
        end
        key = events.keys.first

        broadcast(key, events[key])
      end
    end
  end
end
