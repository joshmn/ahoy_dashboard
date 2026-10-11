module AhoyDashboard
  module SearchConsole
    # One missing day off the queue.
    #
    # The pull is IngestCommand with a single date, the same as the nightly run
    # and the same as the backfill. Nothing about a day in a hole is different
    # from a day at the top of the record, and a second thing that wrote these
    # three tables would be a second thing to keep in agreement.
    #
    # One day a call rather than the whole list, so the count on the jobs screen
    # is the truth at every moment and a worker that dies takes one day's work
    # with it rather than an afternoon's.
    class FillCommand < AhoyDashboard::Command
      Result = Data.define(:date, :rows, :keywords, :totals, :remaining, :filled) do
        def more?
          remaining.positive?
        end
      end

      def initialize(account: nil, queue: nil)
        @account = account
        @queue = queue || FillQueue.load
      end

      def call
        return broadcast(:skipped, "search console is not configured") unless SearchConsole.enabled?
        return broadcast(:skipped, "google is not connected") unless account&.ready?
        return broadcast(:done, "nothing is waiting to be filled") unless queue.running?

        date = queue.next_date
        events = IngestCommand.call(account: account, dates: [ date ], stamp: false)
        return relay(events) unless events.key?(:ok)

        queue.advance!
        broadcast(:ok, result(date, events[:ok]))
      end

      private

      attr_reader :queue

      def account
        @account ||= GoogleAccount.current
      end

      # The day stays on the queue when the pull did not land, so pressing the
      # button again picks it up rather than stepping over it.
      def relay(events)
        key = events.keys.first

        broadcast(key, events[key])
      end

      def result(date, ingested)
        Result.new(
          date: date,
          rows: ingested.rows,
          keywords: ingested.keywords,
          totals: ingested.totals,
          remaining: queue.remaining,
          filled: queue.filled
        )
      end
    end
  end
end
