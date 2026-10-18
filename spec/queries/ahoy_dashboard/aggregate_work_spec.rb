require "rails_helper"

RSpec.describe "Ahoy dashboard aggregate work" do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  before do
    long = dash_landing("/a", at: dash_time(2026, 8, 10, 23, 55), visitor: "returning", country: "US")
    dash_page_view(long, path: "/b", at: dash_time(2026, 8, 11, 0, 5))
    dash_goal(long, AhoyDashboard::ENGAGEMENT, path: "/a", scroll_depth: 40,
              engagement_time: 30, at: dash_time(2026, 8, 11, 0, 6))

    dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "returning", country: "US")

    unbrowsed = dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "searcher", country: nil)
    dash_goal(unbrowsed, "site_searched")

    bot = dash_visit(started_at: dash_time(2026, 8, 10, 11), visitor: "bot", country: "CA")
    dash_page_view(bot, path: "/a", crawler: "GPTBot")
    dash_visit(started_at: dash_time(2026, 8, 10, 12), visitor: "no events", country: "CA")

    dash_landing("/anonymous", at: dash_time(2026, 8, 10, 13), visitor_token: nil, country: "GB")

    dash_landing("/a", at: dash_time(2026, 8, 9, 9), visitor: "previous")
  end

  describe "selected top stats" do
    it "matches the full strip exactly, including comparisons, under each scope variant", :equivalence do
      comparison = dash_scope(range: dash_day_range(2026, 8, 9))
      variants = [
        scope,
        dash_scope(range: range, include_crawlers: true),
        dash_scope(range: range, filters: dash_filters([ "page", "is", "/b" ])),
        dash_scope(range: range, filters: dash_filters([ "country", "is", "(not set)" ])),
        dash_scope(range: dash_day_range(2026, 8, 1))
      ]

      variants.each do |current|
        expected = AhoyDashboard::TopStatsQuery.call(scope: current, comparison_scope: comparison)
        expected.each do |stat|
          selected = AhoyDashboard::TopStatsQuery.call(
            scope: current, comparison_scope: comparison, metrics: [ stat.metric ]
          )

          expect(selected).to eq([ stat ]), "expected #{stat.metric.key} to retain its full-strip value"
          expect(selected.map(&:to_h).to_json).to eq([ stat.to_h ].to_json)
        end
      end
    end

    it "reads only visitor totals for a visitor question" do
      statements = analytics_sql do
        result = AhoyDashboard::TopStatsQuery.call(scope: scope, metrics: %w[visitors])
        expect(result.first.value).to eq(2)
      end

      expect(statements.size).to eq(1)
      expect(statements.first).not_to include("tm_visits", "avg(")
    end

    it "reads only the requested event aggregate for pageviews or scroll depth" do
      %w[pageviews scroll_depth].each do |metric|
        statements = analytics_sql { AhoyDashboard::TopStatsQuery.call(scope: scope, metrics: [ metric ]) }

        expect(statements.size).to eq(1)
        expect(statements.first).not_to include("tm_visits")
      end
    end

    it "reads only one session aggregate for a bounce or duration question" do
      %w[bounce_rate visit_duration].each do |metric|
        statements = analytics_sql { AhoyDashboard::TopStatsQuery.call(scope: scope, metrics: [ metric ]) }

        expect(statements.size).to eq(1)
        expect(statements.first).not_to include("count(distinct tm_visits.visitor_token")
      end
    end

    it "reuses session pageview totals only when no view filter changes what is counted" do
      statements = analytics_sql do
        expect(dash_value(AhoyDashboard::TopStatsQuery.call(scope: scope), "pageviews")).to eq(4)
      end
      expect(statements.size).to eq(2)

      page_filtered = dash_scope(range: range, filters: dash_filters([ "page", "is", "/a" ]))
      statements = analytics_sql do
        result = AhoyDashboard::TopStatsQuery.call(scope: page_filtered)
        expect(dash_value(result, "pageviews")).to eq(2)
        expect(dash_value(result, "views_per_visit")).to eq(1.0)
      end
      expect(statements.size).to eq(3)

      create(:dash_goal, event_name: "site_searched", display_name: "Searched")
      converted = Ahoy::Visit.where(visitor_token: "returning").order(:started_at).last
      dash_goal(converted, "site_searched", at: dash_time(2026, 8, 11, 0, 7))
      goal_filtered = dash_scope(range: range, filters: dash_filters([ "goal", "is", "Searched" ]))
      statements = analytics_sql do
        expect(dash_value(AhoyDashboard::TopStatsQuery.call(scope: goal_filtered), "pageviews")).to eq(2)
      end
      expect(statements.size).to eq(2)
    end
  end

  describe "session ratio series" do
    it "computes each ratio in one statement, including out-of-range session events" do
      { "bounce_rate" => 66.7, "visit_duration" => 165 }.each do |metric, value|
        statements = analytics_sql do
          points = AhoyDashboard::TimeseriesQuery.call(scope: scope, metric: metric)
          expect(points).to eq([ [ range.begin, value ] ])
        end

        expect(statements.size).to eq(1)
      end
    end

    it "reads views per visit off the session pass with the numbers the two separate counts gave", :equivalence do
      create(:dash_goal, event_name: "site_searched", display_name: "Searched")
      wide = dash_day_range(2026, 8, 9).begin..dash_time(2026, 8, 11).end_of_day
      variants = [
        dash_scope(range: wide),
        dash_scope(range: wide, include_crawlers: true),
        dash_scope(range: wide, filters: dash_filters([ "country", "is", "US" ])),
        dash_scope(range: wide, filters: dash_filters([ "goal", "is", "Searched" ])),
        dash_scope(range: wide, filters: dash_filters([ "exit_page", "is", "/b" ])),
        dash_scope(range: range)
      ]

      variants.product(%i[day hour]).each do |current, interval|
        bucket = AhoyDashboard::Sql::Buckets.sql(AhoyDashboard::TimeseriesQuery::VISIT_START, interval)
        views = AhoyDashboard::Sql::Buckets.fill(current.pageviews.group(bucket).count, current.range, interval)
        visits = AhoyDashboard::Sql::Buckets.fill(current.visits.group(bucket).count, current.range, interval)
        expected = visits.map do |time, count|
          [ time, count.zero? ? 0.0 : (views[time].to_f / count).round(2) ]
        end
        actual = nil

        statements = analytics_sql do
          actual = AhoyDashboard::TimeseriesQuery.call(scope: current, metric: "views_per_visit", interval: interval)
        end

        expect(actual).to eq(expected), "#{current.filters.to_a.map(&:dimension).map(&:key)} #{interval}"
        expect(statements.size).to eq(1)
      end
    end

    it "retains full-session ratios under a page filter and fills empty buckets" do
      filtered = dash_scope(
        range: range.begin..dash_time(2026, 8, 11).end_of_day,
        filters: dash_filters([ "page", "is", "/b" ])
      )

      expect(AhoyDashboard::TimeseriesQuery.call(scope: filtered, metric: "bounce_rate").map(&:last))
        .to eq([ 0.0, 0.0 ])
      expect(AhoyDashboard::TimeseriesQuery.call(scope: filtered, metric: "visit_duration").map(&:last))
        .to eq([ 660, 0 ])
    end
  end

  describe "headline stats with a chart" do
    it "preserves every metric, bucket, comparison and filter independently of the shared scan", :equivalence do
      dash_landing("/a", at: dash_time(2026, 8, 9, 15), visitor: "returning")
      wide = dash_day_range(2026, 8, 9).begin..range.end
      variants = [
        dash_scope(range: wide),
        dash_scope(range: wide, include_crawlers: true),
        dash_scope(range: wide, filters: dash_filters([ "page", "is", "/a" ])),
        dash_scope(range: wide, filters: dash_filters([ "country", "is", "(not set)" ])),
        dash_scope(range: dash_day_range(2026, 8, 1))
      ]
      comparison = dash_scope(range: dash_day_range(2026, 8, 9))

      variants.product(AhoyDashboard::Metric::ALL, %i[day hour], [ nil, comparison ]).each do |current, metric, interval, previous|
        expected_stats = AhoyDashboard::TopStatsQuery.call(scope: current, comparison_scope: previous)
        expected_series = AhoyDashboard::TimeseriesQuery.call(scope: current, metric: metric, interval: interval)
        expected_comparison = previous && AhoyDashboard::TimeseriesQuery.call(scope: previous, metric: metric, interval: interval)
        actual = AhoyDashboard::TopStatsQuery.with_series(
          scope: current, comparison_scope: previous, metric: metric, interval: interval
        )

        expect(actual.stats).to eq(expected_stats), "stats for #{metric.key}"
        expect(actual.series.to_json).to eq(expected_series.to_json), "series for #{metric.key}"
        expect(actual.comparison_series.to_json).to eq(expected_comparison.to_json), "comparison for #{metric.key}"
      end
    end

    it "shares the total and buckets and only scans engagement separately" do
      %w[visitors visits views_per_visit bounce_rate visit_duration].each do |metric|
        statements = analytics_sql do
          AhoyDashboard::TopStatsQuery.with_series(scope: scope, metric: metric)
        end

        expect(statements.size).to eq(2), metric
        expect(statements.count { |sql| sql.include?("grouping sets") }).to eq(1)
      end
    end

    it "retains separate event-time and filtered-page calculations" do
      %w[pageviews scroll_depth].each do |metric|
        statements = analytics_sql { AhoyDashboard::TopStatsQuery.with_series(scope: scope, metric: metric) }
        expect(statements.size).to eq(3), metric
      end

      filtered = dash_scope(range: range, filters: dash_filters([ "page", "is", "/a" ]))
      statements = analytics_sql do
        AhoyDashboard::TopStatsQuery.with_series(scope: filtered, metric: "views_per_visit", interval: :unknown)
      end
      expect(statements.size).to eq(5)
    end

    it "keeps the original visitor scan for charts beyond the normal bucket budget" do
      wide = dash_scope(range: range.begin..(range.end + 1.day))
      expected = AhoyDashboard::TimeseriesQuery.call(scope: wide, metric: "visitors", interval: :minute)
      statements = analytics_sql do
        actual = AhoyDashboard::TopStatsQuery.with_series(scope: wide, metric: "visitors", interval: :minute)
        expect(actual.series.to_json).to eq(expected.to_json)
        expect(actual.series.size).to be > AhoyDashboard::Period::MAX_BUCKETS
      end

      expect(statements.size).to eq(3)
      expect(statements.none? { |sql| sql.include?("grouping sets") }).to be(true)
    end
  end

  describe "count series with range totals" do
    it "matches the separate reads for each count metric, range, filter, and bucket size", :equivalence do
      dash_landing("/a", at: dash_time(2026, 8, 9, 15), visitor: "returning")
      wide = dash_day_range(2026, 8, 9).begin..range.end
      variants = [
        dash_scope(range: wide),
        dash_scope(range: wide, include_crawlers: true),
        dash_scope(range: wide, filters: dash_filters([ "page", "is", "/a" ])),
        dash_scope(range: dash_day_range(2026, 8, 1))
      ]

      variants.product(%w[visitors visits pageviews], %i[day hour]).each do |current, metric, interval|
        expected_total = AhoyDashboard::TopStatsQuery.call(scope: current, metrics: [ metric ]).first.value
        expected_series = AhoyDashboard::TimeseriesQuery.call(scope: current, metric: metric, interval: interval)
        combined = AhoyDashboard::TimeseriesQuery.with_total(scope: current, metric: metric, interval: interval)

        expect(combined.total).to eq(expected_total)
        expect(combined.series.to_json).to eq(expected_series.to_json)
      end

      combined = AhoyDashboard::TimeseriesQuery.with_total(scope: variants.first, metric: "visitors")
      expect(combined.total).to eq(3)
      expect(combined.series.sum(&:last)).to eq(4)
    end

    it "executes one statement for the independent total and buckets" do
      statements = analytics_sql do
        AhoyDashboard::TimeseriesQuery.with_total(scope: scope, metric: "visitors")
      end

      expect(statements.size).to eq(1)
      expect(statements.first).to include("grouping sets")
    end
  end

  describe "breakdown projections and session facts" do
    it "counts all matching groups in the paged aggregate without changing the answer", :equivalence do
      variants = [ scope, dash_scope(range: range, include_crawlers: true) ]
      variants.product(%w[country page exit_page], [ %w[visitors], %w[pageviews bounce_rate visit_duration] ], [ nil, 1, 2 ], [ 0, 1 ]).each do |current, key, metrics, limit, offset|
        options = { scope: current, dimension: AhoyDashboard::Dimension.find(key), metrics: metrics, limit: limit, offset: offset }
        expected = AhoyDashboard::BreakdownQuery.call(**options)
        expected_count = AhoyDashboard::BreakdownQuery.call(scope: current, dimension: options[:dimension], limit: nil).rows.size
        actual = AhoyDashboard::BreakdownQuery.with_row_count(**options)

        expect(actual.result).to eq(expected)
        expect(actual.row_count).to eq(expected_count) if actual.result.rows.any?
      end

      dimension = AhoyDashboard::Dimension.find("page")
      [ "ahoy_events.properties ->> 'path' = '/a'", "false" ].each do |search|
        actual = AhoyDashboard::BreakdownQuery.with_row_count(scope: scope, dimension: dimension, search: search)
        expect(actual.row_count).to eq(AhoyDashboard::BreakdownQuery.call(scope: scope, dimension: dimension, search: search, limit: nil).rows.size)
      end
    end

    it "adds the pager count to the existing query rather than counting the groups separately" do
      statements = analytics_sql do
        actual = AhoyDashboard::BreakdownQuery.with_row_count(
          scope: scope, dimension: AhoyDashboard::Dimension.find("page"), limit: 1
        )
        expect(actual.result).to be_more
        expect(actual.row_count).to eq(3)
      end

      expect(statements.size).to eq(2)
      expect(statements.count { |sql| sql.include?("count(*) over ()") }).to eq(1)
      expect(statements.none? { |sql| sql.include?("tm_groups") }).to be(true)
    end

    it "can add a count after the same query instance has already returned its rows" do
      query = AhoyDashboard::BreakdownQuery.new(scope: scope, dimension: AhoyDashboard::Dimension.find("page"), limit: 1)
      original = query.call
      counted = query.with_row_count

      expect(counted.result).to eq(original)
      expect(counted.row_count).to eq(3)
    end

    it "does not calculate unrequested event counts or distinct session counts" do
      statements = analytics_sql do
        result = AhoyDashboard::BreakdownQuery.call(scope: scope, dimension: AhoyDashboard::Dimension.find("page"))
        expect(result.rows.map(&:label)).to eq(%w[/a /b /anonymous])
        expect(result.rows.map(&:metrics)).to eq([ { "visitors" => 1 }, { "visitors" => 1 }, { "visitors" => 0 } ])
      end

      grouped = statements.find { |sql| sql.include?("GROUP BY") }
      expect(grouped).not_to include("count(distinct ahoy_events.visit_id)", "count(*)")
    end

    it "keeps aggregate ordering when the requested metric has no ordering of its own" do
      result = AhoyDashboard::BreakdownQuery.call(
        scope: scope, dimension: AhoyDashboard::Dimension.find("country"), metrics: %w[visit_duration], limit: 1
      )

      expect(result.rows.first.label).to eq("US")
      expect(result.rows.first.metrics).to eq("visit_duration" => 330)
      expect(result).to be_more
    end

    it "keeps all events of matched sessions while limiting work to the returned values" do
      statements = analytics_sql do
        result = AhoyDashboard::BreakdownQuery.call(
          scope: scope, dimension: AhoyDashboard::Dimension.find("page"),
          metrics: %w[visitors bounce_rate visit_duration], search: "ahoy_events.properties ->> 'path' = '/b'"
        )

        expect(result.rows.map(&:label)).to eq([ "/b" ])
        expect(result.rows.first.metrics).to eq("visitors" => 1, "bounce_rate" => 0.0, "visit_duration" => 660)
      end

      sessions = statements.find { |sql| sql.include?("tm_pairs") }
      expect(sessions).to include("ahoy_visits.id in (select visit_id from tm_pairs)")
    end

    it "retains null dimension values in the matching session relation" do
      AhoyDashboard::Dimension.register(
        key: "event_country", label: "Country of event", group: "Location",
        scope: :event, sql: Arel.sql("ahoy_visits.country")
      )
      result = AhoyDashboard::BreakdownQuery.call(
        scope: scope, dimension: AhoyDashboard::Dimension.find("event_country"),
        metrics: %w[visitors bounce_rate visit_duration]
      )

      expect(dash_row(result, "(not set)").metrics)
        .to eq("visitors" => 1, "bounce_rate" => 0.0, "visit_duration" => 0)
    end
  end

  describe "engagement averages without distributions" do
    it "preserves metrics for engagement-only, milestone-only, null, and absent values with one query" do
      visit = Ahoy::Visit.find_by!(visitor_token: "searcher")
      dash_goal(visit, AhoyDashboard::SCROLL_MILESTONE, path: "/milestone-only", depth: 25)
      dash_goal(visit, AhoyDashboard::SCROLL_MILESTONE, path: nil, depth: 50)
      dimension = AhoyDashboard::Dimension.find("page")
      values = [ "/a", "/milestone-only", nil, "/missing" ]
      expected = {
        "/a" => { "scroll_depth" => 40.0, "engagement_time" => 30 },
        "/milestone-only" => { "scroll_depth" => 0.0, "engagement_time" => 0 },
        nil => { "scroll_depth" => 0.0, "engagement_time" => 0 }
      }

      statements = analytics_sql do
        actual = AhoyDashboard::EngagementQuery.call(scope: scope, dimension: dimension, values: values)
          .transform_values(&:metrics)

        expect(actual).to eq(expected)
        expected.each_key { |key| expect(actual.fetch(key).to_json).to eq(expected.fetch(key).to_json) }
      end

      expect(statements.size).to eq(1)
      expect(statements.first).not_to include("properties ->> 'depth'")
    end
  end
end
