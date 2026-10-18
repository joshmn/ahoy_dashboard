# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    Reading = Data.define(:readings, :realtime, :annotations, :reports, :pinned_cards, :search_console_state,
      :search_console, :funnels, :funnel_count, :journey, :goal_conversions, :goals, :computed_at,
      :snapshot_key) do
      def initialize(readings:, realtime:, annotations:, reports: [], pinned_cards: [],
        search_console_state: nil, search_console: nil, funnels: [], funnel_count: 0,
        journey: nil, goal_conversions: nil, goals: [], computed_at: nil, snapshot_key: nil)
        super(readings: readings, realtime: realtime, annotations: annotations, reports: reports,
          pinned_cards: pinned_cards, search_console_state: search_console_state, search_console: search_console,
          funnels: funnels, funnel_count: funnel_count, journey: journey, goal_conversions: goal_conversions,
          goals: goals, computed_at: computed_at, snapshot_key: snapshot_key)
      end
    end
  end
end
