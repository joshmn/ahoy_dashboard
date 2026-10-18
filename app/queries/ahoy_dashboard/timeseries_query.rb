module AhoyDashboard
  class TimeseriesQuery < AhoyDashboard::Query
    INTERVALS = AhoyDashboard::Sql::Buckets::UNITS.keys.freeze
    DEFAULT_INTERVAL = :day
    VISIT_START = Arel.sql('"ahoy_visits"."started_at"').freeze
    SESSION_START = Arel.sql("tm_visits.started_at").freeze
    VISITOR_TOKEN = Sql::VISITOR_TOKEN
    COUNT_METRICS = %w[visitors visits pageviews].freeze
    CountedSeries = Data.define(:total, :series)

    class << self
      def with_total(**options)
        new(**options).with_total
      end

      def interval(value)
        chosen = value.to_s.to_sym

        INTERVALS.include?(chosen) ? chosen : DEFAULT_INTERVAL
      end

      def metric_key(metric)
        metric.respond_to?(:key) ? metric.key : metric.to_s
      end
    end

    def initialize(scope:, metric:, interval: DEFAULT_INTERVAL)
      @scope = scope
      @metric_key = self.class.metric_key(metric)
      @interval = self.class.interval(interval)
    end

    def call
      case metric_key
      when "visits" then series(visits_by_bucket)
      when "pageviews" then series(pageviews_by_bucket)
      when "views_per_visit" then views_per_visit
      when "bounce_rate" then session_ratio(Sql::COUNT_BOUNCED, Sql::COUNT_BROWSED, scale: 100, round: 1)
      when "visit_duration" then session_ratio("sum(tm_visits.duration)", "count(*)", round: 0)
      when "scroll_depth" then percentages(scroll_depth_by_bucket)
      else series(visitors_by_bucket)
      end
    end

    def with_total
      relation = counted_relation
      rows = cached_pluck(relation: relation, columns: relation.select_values)
      total = 0
      counts = {}
      rows.each do |grouped, time, count|
        if grouped == 1
          total = count.to_i
        else
          counts[time] = count
        end
      end

      points = Sql::Buckets.fill(counts, scope.range, interval).map { |time, count| [ time, count.to_i ] }
      CountedSeries.new(total: total, series: points)
    end

    def cache_counted_rows(rows)
      relation = counted_relation
      AnalyticsCache.write(key: ["timeseries", relation.to_sql], value: rows, connection: relation.connection)
    end

    private

    attr_reader :scope, :metric_key, :interval

    def counted_relation
      raise ArgumentError, "no combined count for #{metric_key}" unless COUNT_METRICS.include?(metric_key)

      relation = metric_key == "pageviews" ? scope.pageviews : scope.visits
      column = metric_key == "pageviews" ? clamped_time : VISIT_START
      bucket = Sql::Buckets.sql(column, interval)
      aggregate = metric_key == "visitors" ? "count(distinct #{VISITOR_TOKEN})" : "count(*)"

      relation.group(Arel.sql("grouping sets ((#{bucket}), ())"))
        .reselect(Arel.sql("grouping(#{bucket})"), bucket, Arel.sql(aggregate))
    end

    def by_bucket(relation, column)
      grouped = relation.group(Sql::Buckets.sql(column, interval))

      counts = AnalyticsCache.fetch(key: ["timeseries", metric_key, grouped.to_sql], connection: relation.connection) do
        yield(grouped)
      end

      Sql::Buckets.fill(counts, scope.range, interval)
    end

    def visitors_by_bucket
      by_bucket(scope.visits, VISIT_START) { |grouped| grouped.distinct.count(VISITOR_TOKEN) }
    end

    def visits_by_bucket
      by_bucket(scope.visits, VISIT_START, &:count)
    end

    def pageviews_by_bucket
      by_bucket(scope.pageviews, clamped_time, &:count)
    end

    def clamped_time
      Arel.sql("least(greatest(ahoy_events.time, #{Sql.timestamp(scope.range.begin)}), #{Sql.timestamp(scope.range.end)})")
    end

    def views_per_visit
      return ratio(session_pageviews_by_bucket, visits_by_bucket, round: 2) if scope.view_groups?

      session_ratio(Sql::SESSION_PAGEVIEWS, "count(*)", round: 2)
    end

    def session_pageviews_by_bucket
      by_bucket(scope.pageviews, VISIT_START, &:count)
    end

    def session_ratio(numerator, denominator, scale: 1, round: 0)
      bucket = Sql::Buckets.sql(SESSION_START, interval)
      columns = [bucket, Arel.sql(numerator), Arel.sql(denominator)]
      rows = cached_pluck(relation: scope.sessions.group(bucket), columns: columns)
      counts = rows.map do |time, top, bottom|
        [ time, ratio_value(top, bottom, scale: scale, round: round) ]
      end.to_h

      Sql::Buckets.fill(counts, scope.range, interval, default: ratio_value(0, 0, scale: scale, round: round)).to_a
    end

    def cached_pluck(relation:, columns:)
      sql = relation.reselect(*columns).to_sql

      AnalyticsCache.fetch(key: ["timeseries", sql], connection: relation.connection) { relation.pluck(*columns) }
    end

    def scroll_depth_by_bucket
      relation = scope.visit_events.where(name: AhoyDashboard::ENGAGEMENT)

      by_bucket(relation, clamped_time) { |grouped| grouped.average(AhoyDashboard::EngagementQuery::SCROLL_DEPTH) }
    end

    def series(buckets)
      buckets.map { |time, value| [ time, value.to_i ] }
    end

    def percentages(buckets)
      buckets.map { |time, value| [ time, value.to_f.round(1) ] }
    end

    def ratio(numerators, denominators, scale: 1, round: 0)
      denominators.map do |bucket, denominator|
        [ bucket, ratio_value(numerators[bucket], denominator, scale: scale, round: round) ]
      end
    end

    def ratio_value(numerator, denominator, scale:, round:)
      value = denominator.to_i.zero? ? 0.0 : (numerator.to_f * scale) / denominator

      round.zero? ? value.round : value.round(round)
    end
  end
end
