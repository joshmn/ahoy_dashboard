module AhoyDashboard
  module Seo
    class PropertyTotalsQuery
      Result = Data.define(:clicks, :impressions, :last_date) do
        def any?
          !last_date.nil?
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:, slice: AhoyDashboard::SearchConsole::Slice.new)
        @range = range
        @slice = slice
      end

      def call
        clicks, impressions, last_date = slice.apply(AhoyDashboard::SearchConsoleTotal.in_range(range))
          .pick(Arel.sql("coalesce(sum(clicks), 0)"), Arel.sql("coalesce(sum(impressions), 0)"), Arel.sql("max(date)"))

        Result.new(clicks: clicks.to_i, impressions: impressions.to_i, last_date: last_date)
      end

      private

      attr_reader :range, :slice
    end
  end
end
