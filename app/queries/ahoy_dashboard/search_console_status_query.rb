module AhoyDashboard
  # What the connection page says about the local copy: how much of it there is
  # and how far it runs. Nothing here touches Google, so the page loads without a
  # network call.
  class SearchConsoleStatusQuery
    AGGREGATES = [
      Arel.sql("min(date)"), Arel.sql("max(date)"),
      Arel.sql("sum(clicks)"), Arel.sql("sum(impressions)"), Arel.sql("count(distinct date)")
    ].freeze

    Status = Data.define(:rows, :days, :first_date, :last_date, :expected_last_date, :clicks, :impressions) do
      def any?
        days.positive?
      end

      # The furthest Google will go is three days back, so this is caught up
      # rather than late.
      def current?
        last_date.present? && last_date >= expected_last_date
      end
    end

    def self.call
      new.call
    end

    # The row count is exact and it is a full count over a table nothing ever
    # prunes, which is the one cost on this screen that grows. It stays exact
    # because the screen prints a precise figure, and an estimate printed as one
    # would be a lie; the day it stops being affordable the screen has to start
    # saying "about" first. The day count comes off the aggregate above rather
    # than a second scan of the same table.
    def call
      first, last, clicks, impressions, days = Array(SearchConsoleTotal.pick(*AGGREGATES))

      Status.new(
        rows: SearchConsoleRow.count,
        days: days.to_i,
        first_date: first,
        last_date: last,
        expected_last_date: SearchConsole.latest_final_date,
        clicks: clicks.to_i,
        impressions: impressions.to_i
      )
    end
  end
end
