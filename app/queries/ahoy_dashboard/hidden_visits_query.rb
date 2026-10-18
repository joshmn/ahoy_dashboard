# frozen_string_literal: true

module AhoyDashboard
  class HiddenVisitsQuery < AhoyDashboard::Query
    def initialize(range:)
      @range = range
    end

    def call
      return 0 unless Sql::ExcludedTraffic.enabled?

      visits = AhoyDashboard.visit.where(started_at: range)
      hidden = Sql::ExcludedTraffic.only(visits, floor: range.begin)

      AnalyticsCache.fetch(key: ["hidden_visits", hidden.to_sql], connection: hidden.connection) do
        hidden.count
      end
    end

    private

    attr_reader :range
  end
end
