module AhoyDashboard
  # The numbers across the top of the dashboard, one per chartable metric, and
  # the same set for the comparison range when one is asked for.
  class TopStatsQuery
    Stat = Data.define(:metric, :value, :comparison_value, :change)
    Totals = Data.define(:visitors, :visits, :pageviews, :bounces, :browsed, :duration, :scroll_depth)
    WithSeries = Data.define(:stats, :series, :comparison_series)
    SESSION_SERIES_METRICS = %w[visitors views_per_visit bounce_rate visit_duration].freeze

    SESSION_COLUMNS = {
      visitors: Arel.sql('count(distinct tm_visits.visitor_token collate "C")'),
      visits: Arel.sql("count(*)"),
      pageviews: Arel.sql("coalesce(sum(tm_visits.pageviews), 0)"),
      bounces: Arel.sql(Sql::COUNT_BOUNCED),
      browsed: Arel.sql(Sql::COUNT_BROWSED),
      duration: Arel.sql("coalesce(avg(tm_visits.duration), 0)")
    }.freeze
    VISIT_COLUMNS = {
      visitors: Arel.sql('count(distinct ahoy_visits.visitor_token collate "C")'),
      visits: Arel.sql("count(*)")
    }.freeze

    def self.call(**options)
      new(**options).call
    end

    def self.with_series(scope:, metric:, comparison_scope: nil, interval: TimeseriesQuery::DEFAULT_INTERVAL)
      new(scope: scope, comparison_scope: comparison_scope).with_series(metric: metric, interval: interval)
    end

    # A caller that already counted the current range can still build precisely
    # the same comparison as the strip without counting that range again.
    def self.stat(metric:, value:, comparison_value: nil)
      change = unless comparison_value.nil? || comparison_value.to_f.zero?
        (((value - comparison_value) / comparison_value.to_f) * 100).round
      end

      Stat.new(metric: metric, value: value, comparison_value: comparison_value, change: change)
    end

    def initialize(scope:, comparison_scope: nil, metrics: nil)
      @scope = scope
      @comparison_scope = comparison_scope
      keys = metrics && Array(metrics).map { |metric| metric.respond_to?(:key) ? metric.key : metric.to_s }
      @metrics = AhoyDashboard::Metric::ALL.select { |metric| keys.nil? || keys.include?(metric.key) }
    end

    def call
      current_readings = read_totals(scope)
      previous_readings = comparison_scope && read_totals(comparison_scope)
      stats_for(current_readings, previous_readings)
    end

    def with_series(metric:, interval:)
      key = metric.respond_to?(:key) ? metric.key : metric.to_s
      interval = interval.to_s.to_sym
      interval = TimeseriesQuery::DEFAULT_INTERVAL unless TimeseriesQuery::INTERVALS.include?(interval)
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

    # Session facts share one pass. Without a view filter its pageview counts
    # also give the pageview total; a view filter needs a separate count because
    # it narrows the views, not the events inside those sessions.
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

      # The headline-only bucket aggregates can outweigh the shared scan on an
      # unusually dense visitor chart. Keep the original path beyond the same
      # bucket budget used by the custom-range picker; no points are removed.
      target.range.end - target.range.begin <= Period::MAX_BUCKETS * Sql::Buckets::LENGTHS.fetch(interval)
    end

    # A chart bucket and the headline total can share the session reduction.
    # The grand total has its own distinct visitor count; daily counts cannot
    # be summed because one visitor may return on several days.
    def session_totals_and_series(target, key, interval)
      bucket = Sql::Buckets.sql(TimeseriesQuery::SESSION_START, interval)
      columns = SESSION_COLUMNS.dup
      columns[:duration_sum] = Arel.sql("sum(tm_visits.duration)") if key == "visit_duration"
      relation = AhoyDashboard.visit.unscoped.from(Arel.sql("(#{target.per_visit.to_sql}) tm_visits"))

      relation = relation.group(Arel.sql("grouping sets ((#{bucket}), ())"))
      rows = cached_pluck(relation: relation, columns: [Arel.sql("grouping(#{bucket})"), bucket, *columns.values]) do |fresh|
        target.cache_total_visitors(fresh.find { |row| row.first == 1 }.fetch(2))
        if key == "visitors" && reusable_visitor_counts?(target)
          TimeseriesQuery.new(scope: target, metric: key, interval: interval)
            .cache_counted_rows(fresh.map { |row| row.first(3) })
        end
      end
      rows.yield_self do |rows|
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
    end

    def session_series_value(key, facts)
      case key
      when "visitors" then facts[:visitors].to_i
      when "views_per_visit" then ratio(facts[:pageviews].to_i, facts[:visits]).round(2)
      when "bounce_rate" then ratio(facts[:bounces].to_i * 100, facts[:browsed]).round(1)
      # Keep the chart's sum/count arithmetic, including its rounding, separate
      # from the headline's PostgreSQL AVG.
      when "visit_duration" then ratio(facts[:duration_sum].to_f, facts[:visits]).round
      end
    end

    def reusable_visitor_counts?(target)
      # Session SQL joins the event table directly. A host event scope can
      # narrow the separate human-visit relation, so do not publish over it.
      target.include_crawlers? || AhoyDashboard.event.all.to_sql == AhoyDashboard.event.unscoped.to_sql
    end

    def build_totals(readings)
      sessions = readings[:sessions] || {}

      Totals.new(
        visitors: sessions[:visitors].to_i,
        visits: sessions[:visits].to_i,
        pageviews: (readings[:pageviews] ? readings[:pageviews] : sessions[:pageviews]).to_i,
        bounces: sessions[:bounces].to_i,
        browsed: sessions[:browsed].to_i,
        duration: sessions[:duration].to_f,
        scroll_depth: readings[:scroll_depth].to_f
      )
    end

    # The engagement event carries its own depth, so this is an average over
    # events and there is nothing the per visit table can say about it.
    def scroll_depth_for(target)
      relation = target.visit_events.where(name: AhoyDashboard::ENGAGEMENT)

      cached_pluck(relation: relation, columns: [AhoyDashboard::EngagementQuery::AVERAGE_DEPTH]).first
    end

    def sessions_row(target)
      fields = session_fields
      if wanted?("bounce_rate", "visit_duration")
        relation = AhoyDashboard.visit.unscoped.from(Arel.sql("(#{target.per_visit.to_sql}) tm_visits"))
        columns = SESSION_COLUMNS
        fields += [ :pageviews ] if session_pageviews?(target)
      else
        # A single pinned visitor/visit total needs no per-session event reduction.
        relation = target.visits
        columns = VISIT_COLUMNS
      end

      rows = cached_pluck(relation: relation, columns: fields.map { |field| columns.fetch(field) }) do |fresh|
        target.cache_total_visitors(Array(fresh.first).fetch(fields.index(:visitors))) if fields.include?(:visitors)
      end
      rows.first
        .yield_self { |row| fields.zip(Array(row)).to_h }
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
