module AhoyDashboard
  class TopStatsQuery < AhoyDashboard::Query
    Stat = Data.define(:metric, :value, :comparison_value, :change)
    Totals = Data.define(:visitors, :visits, :pageviews, :bounces, :browsed, :duration, :scroll_depth)
    WithSeries = Data.define(:stats, :series, :comparison_series)
    SESSION_SERIES_METRICS = %w[visitors visits views_per_visit bounce_rate visit_duration].freeze

    SESSION_COLUMNS = {
      visitors: Sql::SESSION_VISITORS,
      visits: Arel.sql("count(*)"),
      pageviews: Sql::SESSION_PAGEVIEWS,
      bounces: Arel.sql(Sql::COUNT_BOUNCED),
      browsed: Arel.sql(Sql::COUNT_BROWSED),
      duration: Sql::SESSION_DURATION
    }.freeze
    VISIT_COLUMNS = {
      visitors: Sql::VISITORS,
      visits: Arel.sql("count(*)")
    }.freeze

    class << self
      def with_series(scope:, metric:, comparison_scope: nil, interval: TimeseriesQuery::DEFAULT_INTERVAL)
        new(scope: scope, comparison_scope: comparison_scope).with_series(metric: metric, interval: interval)
      end

      def stat(metric:, value:, comparison_value: nil)
        change = unless comparison_value.nil? || comparison_value.to_f.zero?
          (((value - comparison_value) / comparison_value.to_f) * 100).round
        end

        Stat.new(metric: metric, value: value, comparison_value: comparison_value, change: change)
      end
    end

    def initialize(scope:, comparison_scope: nil, metrics: nil)
      @scope = scope
      @comparison_scope = comparison_scope
      keys = metrics && Array(metrics).map { |metric| TimeseriesQuery.metric_key(metric) }
      @metrics = AhoyDashboard::Metric::ALL.select { |metric| keys.nil? || keys.include?(metric.key) }
    end

    def call
      current_readings = read_totals(scope)
      previous_readings = comparison_scope && read_totals(comparison_scope)
      stats_for(current_readings, previous_readings)
    end

    def with_series(metric:, interval:)
      key = TimeseriesQuery.metric_key(metric)
      interval = TimeseriesQuery.interval(interval)
      current = read_totals(scope, series_key: key, interval: interval)
      previous = comparison_scope && read_totals(comparison_scope, series_key: key, interval: interval)

      WithSeries.new(
        stats: stats_for(current, previous),
        series: current.fetch(:series),
        comparison_series: previous && previous.fetch(:series)
      )
    end

    private

    attr_reader :scope, :comparison_scope, :metrics

    def stats_for(current_readings, previous_readings)
      current = build_totals(current_readings)
      previous = previous_readings && build_totals(previous_readings)

      metrics.map do |metric|
        value = value_for(metric.key, current)
        comparison = previous && value_for(metric.key, previous)

        self.class.stat(metric: metric, value: value, comparison_value: comparison)
      end
    end

    def read_totals(target, series_key: nil, interval: nil)
      readings = {}
      if series_key
        if shared_session_series?(target, series_key, interval)
          combined = session_totals_and_series(target, series_key, interval)
          readings[:sessions] = combined.fetch(:total)
          readings[:series] = combined.fetch(:series)
        else
          readings[:series] = TimeseriesQuery.call(scope: target, metric: series_key, interval: interval)
        end
      end
      readings[:sessions] ||= sessions_row(target) if session_fields.any?
      if wanted?("pageviews", "views_per_visit") && !session_pageviews?(target)
        readings[:pageviews] = AnalyticsCache.fetch(key: ["top_stats", "pageviews_count", target.pageviews.to_sql],
          connection: target.pageviews.connection) { target.pageviews.count }
      end
      readings[:scroll_depth] = scroll_depth_for(target) if wanted?("scroll_depth")
      readings
    end

    def shared_session_series?(target, key, interval)
      return false unless SESSION_SERIES_METRICS.include?(key)
      return session_pageviews?(target) if key == "views_per_visit"
      return true unless key == "visitors"

      target.range.end - target.range.begin <= Period::MAX_BUCKETS * Sql::Buckets::LENGTHS.fetch(interval)
    end

    def session_totals_and_series(target, key, interval)
      bucket = Sql::Buckets.sql(TimeseriesQuery::SESSION_START, interval)
      columns = SESSION_COLUMNS.dup
      columns[:duration_sum] = Arel.sql("sum(tm_visits.duration)") if key == "visit_duration"
      relation = target.sessions.group(Arel.sql("grouping sets ((#{bucket}), ())"))
      rows = cached_pluck(relation: relation, columns: [Arel.sql("grouping(#{bucket})"), bucket, *columns.values]) do |fresh|
        target.cache_total_visitors(fresh.find { |row| row.first == 1 }.fetch(2))
        if key == "visitors" && reusable_visitor_counts?(target)
          TimeseriesQuery.new(scope: target, metric: key, interval: interval)
            .cache_counted_rows(fresh.map { |row| row.first(3) })
        end
      end
      total = {}
      counts = {}
      rows.each do |grouped, time, *values|
        facts = columns.keys.zip(values).to_h
        if grouped == 1
          total = facts
        else
          counts[time] = session_series_value(key, facts)
        end
      end

      default = session_series_value(key, {})
      { total: total, series: Sql::Buckets.fill(counts, target.range, interval, default: default).to_a }
    end

    def session_series_value(key, facts)
      case key
      when "visitors" then facts[:visitors].to_i
      when "visits" then facts[:visits].to_i
      when "views_per_visit" then ratio(facts[:pageviews].to_i, facts[:visits]).round(2)
      when "bounce_rate" then ratio(facts[:bounces].to_i * 100, facts[:browsed]).round(1)
      when "visit_duration" then ratio(facts[:duration_sum].to_f, facts[:visits]).round
      end
    end

    def reusable_visitor_counts?(target)
      target.include_crawlers? || AhoyDashboard.event.all.to_sql == AhoyDashboard.event.unscoped.to_sql
    end

    def build_totals(readings)
      sessions = readings[:sessions] || {}

      Totals.new(
        visitors: sessions[:visitors].to_i,
        visits: sessions[:visits].to_i,
        pageviews: (readings[:pageviews] || sessions[:pageviews]).to_i,
        bounces: sessions[:bounces].to_i,
        browsed: sessions[:browsed].to_i,
        duration: sessions[:duration].to_f,
        scroll_depth: readings[:scroll_depth].to_f
      )
    end

    def scroll_depth_for(target)
      relation = target.visit_events.where(name: AhoyDashboard::ENGAGEMENT)

      cached_pluck(relation: relation, columns: [AhoyDashboard::EngagementQuery::AVERAGE_DEPTH]).first
    end

    def sessions_row(target)
      fields = session_fields
      if wanted?("bounce_rate", "visit_duration")
        relation = target.sessions
        columns = SESSION_COLUMNS
        fields += [ :pageviews ] if session_pageviews?(target)
      else
        relation = target.visits
        columns = VISIT_COLUMNS
      end

      rows = cached_pluck(relation: relation, columns: fields.map { |field| columns.fetch(field) }) do |fresh|
        target.cache_total_visitors(Array(fresh.first).fetch(fields.index(:visitors))) if fields.include?(:visitors)
      end
      fields.zip(Array(rows.first)).to_h
    end

    def cached_pluck(relation:, columns:)
      sql = relation.reselect(*columns).to_sql

      AnalyticsCache.fetch(key: ["top_stats", sql], connection: relation.connection) do
        rows = relation.pluck(*columns)
        yield(rows) if block_given?
        rows
      end
    end

    def session_pageviews?(target)
      wanted?("bounce_rate", "visit_duration") && wanted?("pageviews", "views_per_visit") &&
        !target.view_groups?
    end

    def session_fields
      @session_fields ||= [].tap do |fields|
        fields << :visitors if wanted?("visitors")
        fields << :visits if wanted?("visits", "views_per_visit")
        fields.concat([ :bounces, :browsed ]) if wanted?("bounce_rate")
        fields << :duration if wanted?("visit_duration")
      end
    end

    def wanted?(*keys)
      metrics.any? { |metric| keys.include?(metric.key) }
    end

    def value_for(key, totals)
      case key
      when "visitors" then totals.visitors
      when "visits" then totals.visits
      when "pageviews" then totals.pageviews
      when "views_per_visit" then ratio(totals.pageviews, totals.visits).round(2)
      when "bounce_rate" then ratio(totals.bounces * 100, totals.browsed).round(1)
      when "visit_duration" then totals.duration.round
      when "scroll_depth" then totals.scroll_depth.round(1)
      else 0
      end
    end

    def ratio(numerator, denominator)
      denominator.to_i.zero? ? 0.0 : numerator / denominator.to_f
    end
  end
end
