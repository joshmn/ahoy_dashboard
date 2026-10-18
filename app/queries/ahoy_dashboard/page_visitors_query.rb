# frozen_string_literal: true

module AhoyDashboard

  class PageVisitorsQuery
    VISITORS = "count(distinct visitor_token collate \"C\")".freeze
    EXTRA_ROWS = 6

    attr_reader :limit

    class << self
      def searched(relation, value:, search:)
        return relation if search.blank?

        relation.having(
          "grouping(#{value}) = 1 or #{value} is null or #{value} ilike :term",
          term: "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        )
      end

      def ordering(value)
        "grouping(#{value}) desc, (#{value} is null) desc, #{VISITORS} desc, #{value} asc"
      end
    end

    def initialize(events:, limit:, search: "")
      @events = events
      @limit = limit
      @search = search
      @source_identity = identity_for(events)
    end

    def call
      @rows ||= AnalyticsCache.pluck(relation: relation, connection: AhoyDashboard.visit.connection,
        columns: [ Arel.sql("grouping(step_value)"), Arel.sql("step_value"), Arel.sql(VISITORS) ])
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

    attr_reader :events, :search, :source_identity

    def identity_for(source)
      event_identity = AnalyticsCache.key(key: source.to_sql, connection: source.connection)
      AnalyticsCache.key(key: event_identity, connection: AhoyDashboard.visit.connection)
    end

    def relation
      @relation ||= begin
        source = events.select(Arel.sql("ahoy_visits.visitor_token as visitor_token"),
          Arel.sql("#{Sql::PAGE_VIEW_STEP} as step_value")).to_sql

        counted = AhoyDashboard.visit.unscoped.from(Arel.sql("(#{source}) tm_journey"))
          .where("step_value is not null")
          .group(Arel.sql("grouping sets ((step_value), ())"))
          .order(Arel.sql(self.class.ordering("step_value")))
          .limit(limit + EXTRA_ROWS)
        self.class.searched(counted, value: "step_value", search: search)
      end
    end
  end
end
