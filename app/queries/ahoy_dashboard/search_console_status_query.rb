module AhoyDashboard
  class SearchConsoleStatusQuery
    AGGREGATES = [
      Arel.sql("min(date)"), Arel.sql("max(date)"),
      SearchConsole::Sums::CLICKS, SearchConsole::Sums::IMPRESSIONS, Arel.sql("count(distinct date)")
    ].freeze

    Status = Data.define(:rows, :days, :first_date, :last_date, :expected_last_date, :clicks, :impressions) do
      def any?
        days.positive?
      end

      def current?
        last_date.present? && last_date >= expected_last_date
      end
    end

    def self.call
      new.call
    end

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
