module AhoyDashboard
  # One metric bucketed across the range, every bucket present even when it is
  # empty, so the chart draws a flat line rather than a gap.
  class TimeseriesQuery
    INTERVALS = AhoyDashboard::Sql::Buckets::UNITS.keys.freeze
    DEFAULT_INTERVAL = :day
    VISIT_START = Arel.sql('"ahoy_visits"."started_at"').freeze
    SESSION_START = Arel.sql("tm_visits.started_at").freeze
    VISITOR_TOKEN = Arel.sql("ahoy_visits.visitor_token collate \"C\"").freeze
    COUNT_METRICS = %w[visitors visits pageviews].freeze
    CountedSeries = Data.define(:total, :series)

    def self.call(**options)
      new(**options).call
    end

    def self.with_total(**options)
      new(**options).with_total
    end

    def initialize(scope:, metric:, interval: DEFAULT_INTERVAL)
      @scope = scope
      @metric_key = metric.respond_to?(:key) ? metric.key : metric.to_s
      @interval = interval.to_s.to_sym
    end

    def call
      case metric_key
      when "visits" then series(visits_by_bucket)
      when "pageviews" then series(pageviews_by_bucket)
      when "views_per_visit" then ratio(session_pageviews_by_bucket, visits_by_bucket, round: 2)
      when "bounce_rate" then session_ratio(Sql::COUNT_BOUNCED, Sql::COUNT_BROWSED, scale: 100, round: 1)
      when "visit_duration" then session_ratio("sum(tm_visits.duration)", "count(*)", round: 0)
      when "scroll_depth" then percentages(scroll_depth_by_bucket)
      else series(visitors_by_bucket)
      end
    end

    # Pinned count metrics need both readings. GROUPING SETS counts the range
    # independently of its buckets: summing daily distinct visitors would count
    # a returning visitor more than once.
    def with_total
      relation = counted_relation
      cached_pluck(relation: relation, columns: relation.select_values).yield_self do |rows|
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
    end

    # Publish only rows just read from PostgreSQL. Re-publishing a cached
    # headline would renew its age when a later panel reads these counts.
    def cache_counted_rows(rows)
      relation = counted_relation
      AnalyticsCache.write(key: ["timeseries", relation.to_sql], value: rows, connection: relation.connection)
    end

    private

    attr_reader :scope, :metric_key

    def interval
      INTERVALS.include?(@interval) ? @interval : DEFAULT_INTERVAL
    end

    def counted_relation
      raise ArgumentError, "no combined count for #{metric_key}" unless COUNT_METRICS.include?(metric_key)

      relation = metric_key == "pageviews" ? scope.pageviews : scope.visits
      column = metric_key == "pageviews" ? clamped_time : VISIT_START
      bucket = Sql::Buckets.sql(column, interval)
      aggregate = metric_key == "visitors" ? "count(distinct #{VISITOR_TOKEN})" : "count(*)"

      relation.group(Arel.sql("grouping sets ((#{bucket}), ())"))
        .reselect(Arel.sql("grouping(#{bucket})"), bucket, Arel.sql(aggregate))
    end

    # Group by the bucket expression, then put the empty buckets back. Sql::Buckets
    # owns both halves so the expression that decides where a row lands and the
    # series that decides which buckets exist cannot disagree.
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

    # Bucketed on the event's own time, pulled back to the edge of the range
    # rather than filtered out of it. A visit that starts at 23:45 on the last
    # day still owns the page it loads at 00:10, and dropping that row would
    # leave the chart one behind the number printed above it.
    def pageviews_by_bucket
      by_bucket(scope.pageviews, clamped_time, &:count)
    end

    def clamped_time
      connection = AhoyDashboard.event.connection
      first = connection.quote(scope.range.begin)
      last = connection.quote(scope.range.end)

      Arel.sql("least(greatest(ahoy_events.time, #{first}::timestamp), #{last}::timestamp)")
    end

    # Views per visit divides two counts that have to be counted the same way,
    # so the numerator is bucketed by the visit's start like the denominator.
    def session_pageviews_by_bucket
      by_bucket(scope.pageviews, VISIT_START, &:count)
    end

    # Both components come off the same per-session reduction. Separate counts
    # rebuilt that reduction twice, even when they were scheduled concurrently.
    def session_ratio(numerator, denominator, scale: 1, round: 0)
      bucket = Sql::Buckets.sql(SESSION_START, interval)
      columns = [bucket, Arel.sql(numerator), Arel.sql(denominator)]
      cached_pluck(relation: session_relation.group(bucket), columns: columns).yield_self do |rows|
        counts = rows.map do |time, top, bottom|
          [ time, ratio_value(top, bottom, scale: scale, round: round) ]
        end.to_h

        Sql::Buckets.fill(counts, scope.range, interval, default: ratio_value(0, 0, scale: scale, round: round)).to_a
      end
    end

    def session_relation
      AhoyDashboard.visit.unscoped.from(Arel.sql("(#{scope.per_visit.to_sql}) tm_visits"))
    end

    def cached_pluck(relation:, columns:)
      sql = relation.reselect(*columns).to_sql

      AnalyticsCache.fetch(key: ["timeseries", sql], connection: relation.connection) { relation.pluck(*columns) }
    end

    # One engagement event is one page view, so the average inside a bucket is
    # that bucket's own reading rather than an average of averages. Bucketed on
    # the event's own time like the pageview count, since it fires when the page
    # is left and that can be after the visit's own day.
    def scroll_depth_by_bucket
      relation = scope.visit_events.where(name: AhoyDashboard::ENGAGEMENT)

      by_bucket(relation, clamped_time) { |grouped| grouped.average(AhoyDashboard::EngagementQuery::SCROLL_DEPTH) }
    end

    def series(buckets)
      buckets.yield_self { |values| values.map { |time, value| [ time, value.to_i ] } }
    end

    def percentages(buckets)
      buckets.yield_self { |values| values.map { |time, value| [ time, value.to_f.round(1) ] } }
    end

    # A ratio is worked out inside each bucket. Averaging the whole range's
    # average across buckets would weight a quiet Sunday like a busy Monday.
    def ratio(numerators, denominators, scale: 1, round: 0)
      denominators.yield_self do |denominator_values|
        numerator_values = numerators

        denominator_values.map do |bucket, denominator|
          [ bucket, ratio_value(numerator_values[bucket], denominator, scale: scale, round: round) ]
        end
      end
    end

    def ratio_value(numerator, denominator, scale:, round:)
      value = denominator.to_i.zero? ? 0.0 : (numerator.to_f * scale) / denominator

      round.zero? ? value.round : value.round(round)
    end
  end
end
