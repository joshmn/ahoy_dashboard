# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class ShowQuery
      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(query:, cards: true)
        @query = query
        @cards = cards
      end

      def call
        readings = TopStatsQuery.with_series(scope: query.scope, comparison_scope: query.comparison_scope,
          metric: query.metric, interval: query.interval)
        result = { readings: readings, realtime: RealtimeQuery.call,
          annotations: ChartAnnotationsQuery.call(range: query.range, bucket: query.interval) }
        Reading.new(**result, **(cards ? card_readings(readings: readings) : {}))
      end

      private

      attr_reader :query, :cards

      def card_readings(readings:)
        reports = Report.cards.reject { |report| report.key == Report::BEHAVIOURS }
        funnels = Funnel.ordered.limit(Funnels::IndexQuery::PAGE_SIZE).includes(funnel_steps: :goal).to_a
        search_console_state = FeatureState.for(:search_console)
        goals = Goal.ordered.to_a
        journey = JourneyQuery.new(scope: query.scope)
        headline = HeadlineReading.new(query: query, readings: readings)

        {
          reports: reports.map { |report| ReportQuery.call(query: query, report: report, page_visitors: journey.page_visitors) },
          pinned_cards: PinnedQuestionsQuery.call(headline: headline),
          search_console_state: search_console_state,
          search_console: (SearchConsoleQuery.call(range: query.range) if search_console_state.installed?),
          funnels: funnels.map { |funnel| FunnelQuery.call(scope: query.scope, funnel: funnel) },
          funnel_count: Funnel.count,
          journey: journey.call,
          goal_conversions: GoalsQuery.call(scope: query.scope, limit: GoalConversionsPresenter::ROWS, goals: goals),
          goals: goals
        }
      end
    end
  end
end
