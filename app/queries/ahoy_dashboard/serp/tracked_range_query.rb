module AhoyDashboard
  module Serp
    class TrackedRangeQuery
      def self.call(**options)
        new(**options).call
      end

      def initialize(query:, checks: SerpCheck.all, now: Time.current)
        @query = query
        @checks = checks
        @now = now.in_time_zone(AhoyDashboard.time_zone)
      end

      def call
        return query.range unless query.period.key == AhoyDashboard::SeoRange::EVERYTHING

        earliest = checks.minimum(:checked_at)

        (earliest || now).in_time_zone(AhoyDashboard.time_zone).beginning_of_day..now.end_of_day
      end

      private

      attr_reader :query, :checks, :now
    end
  end
end
