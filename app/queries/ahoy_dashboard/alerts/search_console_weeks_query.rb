module AhoyDashboard
  module Alerts
    class SearchConsoleWeeksQuery
      DAYS = 7

      Week = Data.define(:starts_on, :ends_on, :clicks, :impressions)

      Result = Data.define(:current, :previous) do
        def ends_on
          current.ends_on
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(now: Time.current)
        @last = AhoyDashboard::SearchConsole.latest_final_date(now: now)
      end

      def call
        return nil unless rows.size == DAYS * 2

        Result.new(current: week(last - (DAYS - 1), last), previous: week(last - (DAYS * 2 - 1), last - DAYS))
      end

      private

      attr_reader :last

      def rows
        @rows ||= AhoyDashboard::SearchConsoleTotal
          .where(date: (last - (DAYS * 2 - 1))..last)
          .group(:date)
          .pluck(:date, Arel.sql("sum(clicks)"), Arel.sql("sum(impressions)"))
          .index_by(&:first)
      end

      def week(starts_on, ends_on)
        days = rows.values_at(*(starts_on..ends_on).to_a)

        Week.new(starts_on: starts_on, ends_on: ends_on,
                 clicks: days.sum { |row| row[1].to_i }, impressions: days.sum { |row| row[2].to_i })
      end
    end
  end
end
