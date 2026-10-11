# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class HeadlineReading
      attr_reader :stat, :series

      def initialize(query:, readings:)
        @stat = readings.stats.find { |reading| reading.metric.key == query.metric.key }
        @series = readings.series
        @criteria = criteria_for(query)
        @signature = signature_for(query)
      end

      def matches?(query:)
        stat && series && criteria == criteria_for(query) && signature == signature_for(query)
      end

      private

      attr_reader :criteria, :signature

      def criteria_for(query)
        [query.metric.key, query.interval, query.range, query.filters.to_param,
          query.include_crawlers?, query.include_internal?, AhoyDashboard.time_zone.name]
      end

      def signature_for(query)
        scope = query.scope
        [AnalyticsCache.key(key: [scope.visits.to_sql, scope.pageviews.to_sql], connection: AhoyDashboard.visit.connection),
          AnalyticsCache.key(key: scope.visit_events.to_sql, connection: AhoyDashboard.event.connection)]
      end
    end
  end
end
