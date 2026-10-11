# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class ShowPresenter
      attr_reader :query, :chart, :computed_at

      delegate :chart_data, :chart_options, :tiles, :comparison_label, :range_label, :realtime,
        :interval_options, :comparison_options, :as_json, to: :chart

      def initialize(query:, result:)
        @query = query
        @result = result
        @computed_at = result.computed_at.in_time_zone(AhoyDashboard.time_zone) if result.computed_at
        readings = result.readings
        @chart = DashboardPresenter.new(query: query, stats: readings.stats, series: readings.series,
          comparison_series: readings.comparison_series, realtime: result.realtime,
          annotations: result.annotations, selectable: true)
      end

      def computed_at_label
        computed_at.strftime("%b %-d, %Y at %-l:%M:%S %p %Z") if computed_at
      end

      def fragment_cache_key
        [result.snapshot_key, result.computed_at.iso8601(9)] if result.snapshot_key && result.computed_at
      end

      def report_presenters
        @report_presenters ||= result.reports.map { |reading| ReportPresenter.new(query: query, **reading) }
      end

      def grid_reports
        report_presenters.map(&:report)
      end

      def pinned_cards
        @pinned_cards ||= result.pinned_cards.map { |reading| PinnedQuestionPresenter.new(reading: reading) }
      end

      def search_console_state
        result.search_console_state
      end

      def search_console
        return unless result.search_console

        @search_console ||= SearchConsolePresenter.new(query: query, result: result.search_console)
      end

      def funnel_presenters
        @funnel_presenters ||= result.funnels.map do |reading|
          FunnelPresenter.new(query: query, funnel: reading.funnel, result: reading)
        end
      end

      def funnels
        funnel_presenters.map(&:funnel)
      end

      def funnel_count
        result.funnel_count
      end

      def more_funnels?
        funnel_count > funnel_presenters.length
      end

      def journey
        @journey ||= JourneyPresenter.new(query: query, result: result.journey)
      end

      def goal_conversions
        @goal_conversions ||= GoalConversionsPresenter.new(query: query, result: result.goal_conversions, goals: result.goals)
      end

      private

      attr_reader :result
    end
  end
end
