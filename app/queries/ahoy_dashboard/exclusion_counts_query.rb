module AhoyDashboard
  class ExclusionCountsQuery < AhoyDashboard::Query
    WINDOW = 30.days

    def initialize(filters:, floor: nil)
      @filters = Array(filters)
      @floor = floor || default_floor
    end

    def call
      conditions = filters.map { |set| set && AhoyDashboard::Sql::ExcludedTraffic.match_sql(set, floor: floor) }
      live = conditions.compact
      return conditions.map { nil } if live.empty?

      relation = AhoyDashboard.visit.unscoped.where(AhoyDashboard.visit.arel_table[:started_at].gteq(floor))
      columns = live.map { |sql| Arel.sql("count(*) filter (where coalesce((#{sql}), false))") }
      counts = AnalyticsCache.fetch(key: relation.reselect(*columns).to_sql, connection: relation.connection) do
        Array.wrap(relation.pick(*columns))
      end
      counts = counts.dup

      conditions.map { |sql| sql && counts.shift.to_i }
    end

    private

    attr_reader :filters, :floor

    def default_floor
      seconds = ScopeQuery::TOTAL_TTL.to_i

      Time.at(WINDOW.ago.to_i / seconds * seconds).in_time_zone
    end
  end
end
