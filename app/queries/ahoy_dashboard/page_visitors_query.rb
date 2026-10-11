# frozen_string_literal: true

module AhoyDashboard

  class PageVisitorsQuery
    VISITORS = "count(distinct visitor_token collate \"C\")".freeze
    EXTRA_ROWS = 6

    attr_reader :limit

    def initialize(events:, limit:)
      @events = events
      @limit = limit
      @source_identity = identity_for(events)
    end

    def call
      @rows ||= begin
        columns = [Arel.sql("grouping(step_value)"), Arel.sql("step_value"), Arel.sql(VISITORS)]
        AnalyticsCache.fetch(key: relation.reselect(*columns).to_sql, connection: AhoyDashboard.visit.connection) do
          relation.pluck(*columns)
        end
      end
    end

    def report_result(scope:, dimension:, limit:)
      return unless dimension.key == "page" && dimension.sql.to_s == Sql::EVENT_PATH.to_s && dimension.exclude.nil?
      return unless limit <= self.limit && scope.views_for(dimension).to_sql == events.to_sql
      return unless source_identity == identity_for(scope.views_for(dimension))

      counted = call.select { |grouped, _value, _visitors| grouped.zero? }
      names = dimension.labels_for(counted.first(limit).map { |_grouped, value, _visitors| value })
      rows = counted.first(limit).map do |_grouped, value, visitors|
        value = value.presence
        BreakdownQuery::Row.new(label: names[value] || value || dimension.unknown_label,
          value: value, metrics: {"visitors" => visitors.to_i})
      end
      BreakdownQuery::Result.new(rows: rows, total: scope.total_visitors, more: counted.size > limit)
    end

    private

    attr_reader :events, :source_identity

    def identity_for(source)
      event_identity = AnalyticsCache.key(key: source.to_sql, connection: source.connection)
      AnalyticsCache.key(key: event_identity, connection: AhoyDashboard.visit.connection)
    end

    def relation
      @relation ||= begin
        expression = "(case when ahoy_events.name = #{Sql.literal(AhoyDashboard::PAGE_VIEW)} " \
          "then nullif(#{Sql::EVENT_PATH}, '') end) collate \"C\""
        source = events.select(Arel.sql("ahoy_visits.visitor_token as visitor_token"),
          Arel.sql("#{expression} as step_value")).to_sql

        AhoyDashboard.visit.unscoped.from(Arel.sql("(#{source}) tm_journey"))
          .where("step_value is not null")
          .group(Arel.sql("grouping sets ((step_value), ())"))
          .order(Arel.sql("grouping(step_value) desc, (step_value is null) desc, #{VISITORS} desc, step_value asc"))
          .limit(limit + EXTRA_ROWS)
      end
    end
  end
end
