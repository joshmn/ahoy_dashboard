module AhoyDashboard
  class BreakdownQuery < AhoyDashboard::Query
    Row = Data.define(:label, :value, :metrics)

    Result = Data.define(:rows, :total, :more) do
      def more?
        more
      end
    end
    WithRowCount = Data.define(:result, :row_count)

    DEFAULT_METRICS = %w[visitors].freeze
    SESSION_METRICS = %w[bounce_rate visit_duration].freeze
    PER_VISIT_METRICS = %w[pageviews bounce_rate visit_duration].freeze
    ENGAGEMENT_METRICS = %w[scroll_depth engagement_time].freeze
    MAX_LIMIT = 1_000

    VISITORS = Sql::VISITORS
    EVENT_VISITS = Arel.sql("count(distinct ahoy_events.visit_id)").freeze
    EVENT_PAGEVIEWS = Sql::PAGEVIEW_COUNT
    EVENT_COUNT = Arel.sql("count(*)").freeze
    DIMENSION_VALUE = Arel.sql("tm_visits.dimension_value").freeze
    PAIR_VALUE = Arel.sql("tm_dim.dimension_value").freeze
    SESSION_VISITORS = Sql::SESSION_VISITORS
    SESSION_VISITS = Arel.sql("count(*)").freeze
    SESSION_PAGEVIEWS = Sql::SESSION_PAGEVIEWS
    SESSION_BOUNCES = Arel.sql(Sql::COUNT_BOUNCED).freeze
    SESSION_BROWSED = Arel.sql(Sql::COUNT_BROWSED).freeze
    SESSION_DURATION = Sql::SESSION_DURATION

    PLAIN_VISITS = Arel.sql("count(*)").freeze

    VISIT_ORDERS = { "visitors" => VISITORS, "visits" => PLAIN_VISITS }.freeze
    SESSION_ORDERS = { "visitors" => SESSION_VISITORS, "visits" => SESSION_VISITS,
                       "pageviews" => SESSION_PAGEVIEWS }.freeze
    EVENT_ORDERS = { "visitors" => VISITORS, "visits" => EVENT_VISITS,
                     "pageviews" => EVENT_PAGEVIEWS, "events" => EVENT_COUNT }.freeze

    def self.with_row_count(**options)
      new(**options).with_row_count
    end

    def initialize(scope:, dimension:, metrics: DEFAULT_METRICS, limit: 9, offset: 0, search: nil)
      @scope = scope
      @dimension = dimension
      @search = search.presence
      @metrics = Array(metrics).map(&:to_s).presence || DEFAULT_METRICS
      @limit = limit.nil? ? nil : limit.to_i.clamp(1, MAX_LIMIT)
      @offset = [ offset.to_i, 0 ].max
    end

    def call
      return Result.new(rows: rows, total: total, more: false) if limit.nil?

      Result.new(rows: rows.first(limit), total: total, more: rows.size > limit)
    end

    def with_row_count
      @rows = nil unless @count_rows
      @count_rows = true
      result = call
      WithRowCount.new(result: result, row_count: @row_count)
    end

    private

    attr_reader :scope, :dimension, :metrics, :limit, :offset, :search

    def page_size
      limit.nil? ? nil : limit + 1
    end

    def rows
      @rows ||= dimension.event? ? event_rows : visit_rows
    end

    def total
      scope.total_visitors
    end

    def visit_rows
      (metrics & PER_VISIT_METRICS).any? ? session_rows : plain_visit_rows
    end

    def plain_visit_rows
      ordering = ranked_by(VISIT_ORDERS)
      relation = visit_relation
        .group(grouped_value)
        .order(Arel.sql("#{ordering} desc"), grouped_value)
        .limit(page_size)
        .offset(offset)
      counted = pluck_rows(relation, grouped_value,
                           metric_column("visitors", VISITORS, ordering), metric_column("visits", PLAIN_VISITS, ordering))

      engagement = engagement_metrics(counted.map(&:first))
      named = dimension.labels_for(counted.map(&:first))

      counted.map do |value, visitors, visits|
        build_row(value, {
          "visitors" => visitors.to_i, "visits" => visits.to_i
        }.merge(engagement[value] || {}), named)
      end
    end

    def session_rows
      ordering = ranked_by(SESSION_ORDERS)
      relation = scope.sessions(dimension_sql: dimension.sql, exits: dimension.exits?, where: narrowing)
        .group(DIMENSION_VALUE)
        .order(Arel.sql("#{ordering} desc"), DIMENSION_VALUE)
        .limit(page_size)
        .offset(offset)
      counted = pluck_rows(relation, DIMENSION_VALUE,
               metric_column("visitors", SESSION_VISITORS, ordering),
               metric_column("visits", SESSION_VISITS, ordering),
               metric_column("pageviews", SESSION_PAGEVIEWS, ordering),
               metric_column("bounce_rate", SESSION_BOUNCES),
               metric_column("bounce_rate", SESSION_BROWSED),
               metric_column("visit_duration", SESSION_DURATION))

      engagement = engagement_metrics(counted.map(&:first))
      named = dimension.labels_for(counted.map(&:first))

      counted.map do |value, visitors, visits, pageviews, bounces, browsed, duration|
        build_row(
          value,
          session_metrics(visitors, visits, pageviews, bounces, browsed, duration)
            .merge(engagement[value] || {}),
          named
        )
      end
    end

    def event_rows
      ordering = ranked_by(EVENT_ORDERS)
      relation = event_relation
        .group(grouped_value)
        .order(Arel.sql("#{ordering} desc"), grouped_value)
        .limit(page_size)
        .offset(offset)
      counted = pluck_rows(relation, grouped_value,
               metric_column("visitors", VISITORS, ordering),
               metric_column("visits", EVENT_VISITS, ordering),
               metric_column("pageviews", EVENT_PAGEVIEWS, ordering),
               metric_column("events", EVENT_COUNT, ordering))

      sessions = event_session_metrics(counted.map(&:first))

      engagement = engagement_metrics(counted.map(&:first))
      named = dimension.labels_for(counted.map(&:first))

      counted.map do |value, visitors, visits, pageviews, events|
        build_row(value, {
          "visitors" => visitors.to_i, "visits" => visits.to_i,
          "pageviews" => pageviews.to_i, "events" => events.to_i
        }.merge(sessions[value] || {}).merge(engagement[value] || {}), named)
      end
    end

    def ranked_by(orders)
      orders.fetch(metrics.first) { orders.fetch("visitors") }
    end

    def metric_column(key, expression, ordering = nil)
      metrics.include?(key) || ordering == expression ? expression : Arel.sql("0")
    end

    def pluck_rows(relation, *columns)
      columns = columns.each_with_index.map { |column, index| Arel.sql("#{column} AS dash_column_#{index}") }
      columns << Arel.sql("count(*) over ()") if @count_rows
      rows = if limit.nil?
        relation.pluck(*columns)
      else
        AnalyticsCache.pluck(relation: relation, columns: columns, connection: AhoyDashboard.visit.connection)
      end
      return rows unless @count_rows

      @row_count = rows.first&.last || (0 if offset.zero?)
      rows.map { |row| row[0...-1] }
    end

    def grouped_value
      @grouped_value ||= Arel.sql("(#{dimension.sql})::text collate \"C\"")
    end

    def engagement_metrics(values)
      return {} if (metrics & ENGAGEMENT_METRICS).empty? || values.empty?

      AhoyDashboard::EngagementQuery.call(scope: scope, dimension: dimension, values: values).transform_values(&:metrics)
    end

    def visit_relation
      narrow(dimension.exits? ? scope.with_exits : scope.visits)
    end

    def narrow(relation)
      narrowing ? relation.where(narrowing) : relation
    end

    def narrowing
      @narrowing ||= [ exclusion, search ].compact.map { |condition| "(#{condition})" }.join(" and ").presence
    end

    def exclusion
      @exclusion ||= Sql.dimension_inclusion(dimension, floor: scope.range.begin)
    end

    def event_relation
      base = narrow(scope.views_for(dimension))
      return base unless property_dimension?

      base.where("#{dimension.sql} is not null and #{dimension.sql} <> ''")
    end

    def event_session_metrics(values)
      return {} if (metrics & SESSION_METRICS).empty? || values.empty?

      AnalyticsCache.select_rows(sql: session_pairs_sql(values), connection: AhoyDashboard.visit.connection)
        .map do |value, bounces, browsed, duration|
          [ value, { "bounce_rate" => rate(bounces, browsed), "visit_duration" => duration.to_f.round } ]
        end.to_h
    end

    def session_pairs_sql(values)
      pairs = scope.views_for(dimension).select(
        Arel.sql("distinct (#{dimension.sql}) as dimension_value, ahoy_events.visit_id as visit_id")
      ).to_sql
      matching = Sql.value_in(AhoyDashboard.visit.unscoped.from(Arel.sql("(#{pairs}) tm_dim")), PAIR_VALUE, values)
        .select(Arel.sql("tm_dim.dimension_value, tm_dim.visit_id"))
      sessions = scope.per_visit.where(Arel.sql("ahoy_visits.id in (select visit_id from tm_pairs)"))

      <<~SQL
        WITH tm_pairs AS (#{matching.to_sql})
        SELECT #{PAIR_VALUE}, #{metric_column("bounce_rate", SESSION_BOUNCES)},
               #{metric_column("bounce_rate", SESSION_BROWSED)},
               #{metric_column("visit_duration", SESSION_DURATION)}
        FROM tm_pairs tm_dim
        JOIN (#{sessions.to_sql}) tm_visits ON tm_visits.id = tm_dim.visit_id
        GROUP BY #{PAIR_VALUE}
      SQL
    end

    def session_metrics(visitors, visits, pageviews, bounces, browsed, duration)
      {
        "visitors" => visitors.to_i,
        "visits" => visits.to_i,
        "pageviews" => pageviews.to_i,
        "bounce_rate" => rate(bounces, browsed),
        "visit_duration" => duration.to_f.round
      }
    end

    def build_row(value, computed, names = {})
      label = value.presence

      Row.new(
        label: names[label] || label || dimension.unknown_label,
        value: label,
        metrics: metrics.index_with { |key| computed.fetch(key, 0) }
      )
    end

    def rate(numerator, denominator)
      denominator.to_i.zero? ? 0.0 : ((numerator.to_f * 100) / denominator).round(1)
    end

    def property_dimension?
      dimension.sql.to_s.include?("properties ->>")
    end
  end
end
