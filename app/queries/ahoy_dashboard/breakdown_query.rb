module AhoyDashboard
  # The workhorse behind every card: one dimension, the requested metrics, a
  # window of rows and whether there are more of them.
  class BreakdownQuery
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

    VISITORS = Arel.sql("count(distinct ahoy_visits.visitor_token collate \"C\")").freeze
    EVENT_VISITS = Arel.sql("count(distinct ahoy_events.visit_id)").freeze
    EVENT_PAGEVIEWS = Arel.sql("count(*) filter (where ahoy_events.name = 'page_view')").freeze
    EVENT_COUNT = Arel.sql("count(*)").freeze
    DIMENSION_VALUE = Arel.sql("tm_visits.dimension_value").freeze
    PAIR_VALUE = Arel.sql("tm_dim.dimension_value").freeze
    SESSION_VISITORS = Arel.sql("count(distinct tm_visits.visitor_token collate \"C\")").freeze
    SESSION_VISITS = Arel.sql("count(*)").freeze
    SESSION_PAGEVIEWS = Arel.sql("coalesce(sum(tm_visits.pageviews), 0)").freeze
    SESSION_BOUNCES = Arel.sql(Sql::COUNT_BOUNCED).freeze
    SESSION_BROWSED = Arel.sql(Sql::COUNT_BROWSED).freeze
    SESSION_DURATION = Arel.sql("coalesce(avg(tm_visits.duration), 0)").freeze

    PLAIN_VISITS = Arel.sql("count(*)").freeze

    VISIT_ORDERS = { "visitors" => VISITORS, "visits" => PLAIN_VISITS }.freeze
    SESSION_ORDERS = { "visitors" => SESSION_VISITORS, "visits" => SESSION_VISITS,
                       "pageviews" => SESSION_PAGEVIEWS }.freeze
    EVENT_ORDERS = { "visitors" => VISITORS, "visits" => EVENT_VISITS,
                     "pageviews" => EVENT_PAGEVIEWS, "events" => EVENT_COUNT }.freeze

    def self.call(**options)
      new(**options).call
    end

    def self.with_row_count(**options)
      new(**options).with_row_count
    end

    def self.row_count(scope:, dimension:, search: nil)
      new(scope: scope, dimension: dimension, limit: nil, search: search).row_count
    end

    def initialize(scope:, dimension:, metrics: DEFAULT_METRICS, limit: 9, offset: 0, search: nil)
      @scope = scope
      @dimension = dimension
      @search = search.presence
      @metrics = Array(metrics).map(&:to_s).presence || DEFAULT_METRICS
      # nil is "every row there is", which is what an export asks for. A number
      # is a screenful and stays clamped, because a card asking for a million
      # rows is a bug rather than a request.
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

    def row_count
      relation = dimension.scope.to_sym == :event ? event_relation : visit_relation
      groups = relation.unscope(:order, :select).select(Arel.sql("1")).group(grouped_value).to_sql

      AhoyDashboard.visit.unscoped.from(Arel.sql("(#{groups}) tm_groups")).count
    end

    private

    attr_reader :scope, :dimension, :metrics, :limit, :offset, :search

    # One row past the page, so the card knows whether to draw a next link.
    # nil removes the clause entirely.
    def page_size
      limit.nil? ? nil : limit + 1
    end

    def rows
      @rows ||= dimension.scope.to_sym == :event ? event_rows : visit_rows
    end

    def total
      scope.total_visitors
    end

    def visit_rows
      (metrics & PER_VISIT_METRICS).any? ? session_rows : plain_visit_rows
    end

    # Visitors and visits are two counts off the visits table, so a card asking
    # for nothing else never pays for the per visit aggregate.
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
      relation = AhoyDashboard.visit
        .unscoped
        .from(Arel.sql("(#{per_visit_sql}) tm_visits"))
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

    # Scroll depth and time on page come off the engagement event rather than the
    # rows being counted, so they are read for the values this page of the
    # breakdown already returned and merged in, the same way the session metrics
    # are. A card that asks for neither pays for nothing.
    def ranked_by(orders)
      orders.fetch(metrics.first) { orders.fetch("visitors") }
    end

    # Keep the row shape stable without calculating aggregates the caller will
    # discard. The ordering aggregate still has to be evaluated for pagination.
    def metric_column(key, expression, ordering = nil)
      metrics.include?(key) || ordering == expression ? expression : Arel.sql("0")
    end

    # Explore needs the number of groups for its page indicator. The grouping
    # already visits all of them before LIMIT, so count those rows there instead
    # of repeating the filtered scan in a second GROUP BY.
    def pluck_rows(relation, *columns)
      # Rails 6 deduplicates identical projections. Omitted metrics each use
      # zero, so unique aliases keep those placeholders in their row slots.
      columns = columns.each_with_index.map { |column, index| Arel.sql("#{column} AS dash_column_#{index}") }
      columns << Arel.sql("count(*) over ()") if @count_rows
      rows = if limit.nil?
        relation.pluck(*columns)
      else
        AnalyticsCache.fetch(key: relation.reselect(*columns).to_sql, connection: AhoyDashboard.visit.connection) do
          relation.pluck(*columns)
        end
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

      AhoyDashboard::EngagementQuery
        .call(scope: scope, dimension: dimension, values: values, include_milestones: false)
        .transform_values(&:metrics)
    end

    def per_visit_sql
      scope.per_visit(dimension_sql: dimension.sql, exits: exits?, where: narrowing).to_sql
    end

    def visit_relation
      narrow(exits? ? scope.with_exits : scope.visits)
    end

    def narrow(relation)
      narrowing ? relation.where(narrowing) : relation
    end

    def narrowing
      @narrowing ||= [ exclusion, search ].compact.map { |condition| "(#{condition})" }.join(" and ").presence
    end

    def exclusion
      @exclusion ||= Sql.dimension_inclusion(dimension)
    end

    # An event that never carried the key is not "not set", it is a different
    # kind of event, and a goal conversion has no business showing up as a blank
    # row on the top pages card.
    def event_relation
      base = narrow(scope.views_for(dimension))
      return base unless property_dimension?

      base.where("#{dimension.sql} is not null and #{dimension.sql} <> ''")
    end

    # Bounce rate and duration belong to the session, so on an event dimension
    # they are read over the visits that contain a matching event rather than
    # over the events themselves.
    def event_session_metrics(values)
      return {} if (metrics & SESSION_METRICS).empty? || values.empty?

      AhoyDashboard.visit.connection.select_rows(session_pairs_sql(values))
        .map do |value, bounces, browsed, duration|
          [ value, { "bounce_rate" => rate(bounces, browsed), "visit_duration" => duration.to_f.round } ]
        end.to_h
    end

    def session_pairs_sql(values)
      pairs = scope.views_for(dimension).select(
        Arel.sql("distinct (#{dimension.sql}) as dimension_value, ahoy_events.visit_id as visit_id")
      ).to_sql
      matching = restrict(AhoyDashboard.visit.unscoped.from(Arel.sql("(#{pairs}) tm_dim")), values)
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

    def restrict(relation, values)
      present = values.compact
      blanks = values.size > present.size

      return relation.where("tm_dim.dimension_value is null") if present.empty?
      return relation.where("tm_dim.dimension_value in (?) or tm_dim.dimension_value is null", present) if blanks

      relation.where("tm_dim.dimension_value in (?)", present)
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

    # names is what this page's values mean, looked up once for the whole page
    # the way the engagement and session metrics are. label is what is drawn and
    # value is what a filter is built from, so a renamed row still narrows to
    # what was recorded.
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

    def exits?
      dimension.sql.to_s.include?(ExitPagesQuery::ALIAS)
    end

    def property_dimension?
      dimension.sql.to_s.include?("properties ->>")
    end
  end
end
