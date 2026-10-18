module AhoyDashboard
  module SearchConsole
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
