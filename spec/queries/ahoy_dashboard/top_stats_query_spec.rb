require "rails_helper"

RSpec.describe AhoyDashboard::TopStatsQuery do
  let(:range) { dash_day_range(2026, 8, 10) }

  before do
    long = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a")
    dash_page_view(long, path: "/a", at: dash_time(2026, 8, 10, 9, 0))
    dash_page_view(long, path: "/b", at: dash_time(2026, 8, 10, 9, 2))
    dash_page_view(long, path: "/c", at: dash_time(2026, 8, 10, 9, 5))

    returning = dash_visit(started_at: dash_time(2026, 8, 10, 12), visitor: "a")
    dash_page_view(returning, path: "/a", at: dash_time(2026, 8, 10, 12, 0))

    second = dash_visit(started_at: dash_time(2026, 8, 10, 15), visitor: "b")
    dash_page_view(second, path: "/a", at: dash_time(2026, 8, 10, 15, 0))
    dash_goal(second, "site_searched", at: dash_time(2026, 8, 10, 15, 5))
    dash_page_view(second, path: "/d", at: dash_time(2026, 8, 10, 15, 10))

    third = dash_visit(started_at: dash_time(2026, 8, 10, 18), visitor: "c")
    dash_page_view(third, path: "/a", at: dash_time(2026, 8, 10, 18, 0))

    bot = dash_visit(started_at: dash_time(2026, 8, 10, 20), visitor: "bot")
    dash_page_view(bot, path: "/a.md", at: dash_time(2026, 8, 10, 20), crawler: "GPTBot")

    dash_landing("/a", at: dash_time(2026, 8, 9, 12), visitor: "d")
  end

  let(:stats) { described_class.call(scope: dash_scope(range: range)) }

  it "returns one stat per metric, in the metric registry's order" do
    expect(stats.map { |stat| stat.metric.key }).to eq(AhoyDashboard::Metric::ALL.map(&:key))
  end

  it "counts unique visitors across sessions" do
    expect(dash_value(stats, "visitors")).to eq(3)
  end

  it "counts every session" do
    expect(dash_value(stats, "visits")).to eq(4)
  end

  it "counts page views and nothing else" do
    expect(dash_value(stats, "pageviews")).to eq(7)
  end

  it "divides views by visits" do
    expect(dash_value(stats, "views_per_visit")).to eq(1.75)
  end

  it "calls a one pageview session a bounce" do
    expect(dash_value(stats, "bounce_rate")).to be_within(0.001).of(50.0)
  end

  it "keeps a session with no page view out of the bounce rate" do
    searched = dash_visit(started_at: dash_time(2026, 8, 10, 19), visitor: "f")
    dash_goal(searched, "site_searched", at: dash_time(2026, 8, 10, 19))

    expect(dash_value(stats, "visits")).to eq(5)
    expect(dash_value(stats, "bounce_rate")).to be_within(0.001).of(50.0)
  end

  it "measures a session from its start to its last event" do
    expect(dash_value(stats, "visit_duration")).to be_within(0.001).of(225.0)
  end

  describe "scroll depth" do
    before do
      first = dash_landing("/a", at: dash_time(2026, 8, 10, 16), visitor: "e")
      dash_engagement(first, depth: 40, time: 30, at: dash_time(2026, 8, 10, 16))

      second = dash_landing("/a", at: dash_time(2026, 8, 10, 17), visitor: "f")
      dash_engagement(second, depth: 80, time: 90, at: dash_time(2026, 8, 10, 17))
    end

    it "averages the depth every engagement event reported" do
      expect(dash_value(stats, "scroll_depth")).to be_within(0.001).of(60.0)
    end

    it "reads past a depth the client never should have sent" do
      junk = dash_landing("/a", at: dash_time(2026, 8, 10, 19), visitor: "g")
      dash_engagement(junk, depth: "all of it", at: dash_time(2026, 8, 10, 19))

      expect(dash_value(stats, "scroll_depth")).to be_within(0.001).of(60.0)
    end

    it "caps a depth above one hundred rather than letting it move the average" do
      over = dash_landing("/a", at: dash_time(2026, 8, 10, 19), visitor: "g")
      dash_engagement(over, depth: 9_999, at: dash_time(2026, 8, 10, 19))

      expect(dash_value(stats, "scroll_depth")).to be_within(0.001).of(73.3)
    end
  end

  it "leaves crawlers and out of range sessions out of all six" do
    with_bots = described_class.call(scope: dash_scope(range: range, include_crawlers: true))

    expect(dash_value(with_bots, "visitors")).to eq(4)
    expect(dash_value(with_bots, "visits")).to eq(5)
    expect(dash_value(with_bots, "pageviews")).to eq(8)
    expect(dash_value(with_bots, "views_per_visit")).to eq(1.6)
    expect(dash_value(with_bots, "bounce_rate")).to be_within(0.001).of(60.0)
    expect(dash_value(with_bots, "visit_duration")).to be_within(0.001).of(180.0)
  end

  describe "under a page filter" do
    it "reports the sessions that saw the page and the views of it" do
      scope = dash_scope(range: range, filters: dash_filters([ "page", "is", "/d" ]))
      filtered = described_class.call(scope: scope)

      expect(dash_value(filtered, "visitors")).to eq(1)
      expect(dash_value(filtered, "visits")).to eq(1)
      expect(dash_value(filtered, "pageviews")).to eq(1)
    end
  end

  describe "against an empty range" do
    let(:range) { dash_day_range(2026, 8, 1) }

    it "reports zero for every metric rather than nil or a divide by zero" do
      expect(stats.map(&:value)).to eq([ 0, 0, 0, 0, 0, 0, 0 ])
    end
  end

  describe "with a comparison" do
    let(:comparison_scope) { dash_scope(range: dash_day_range(2026, 8, 9)) }
    let(:compared) { described_class.call(scope: dash_scope(range: range), comparison_scope: comparison_scope) }

    it "carries the comparison value and the signed percent change" do
      expect(dash_stat(compared, "visitors").comparison_value).to eq(1)
      expect(dash_stat(compared, "visitors").change).to eq(200)
      expect(dash_stat(compared, "visits").comparison_value).to eq(1)
      expect(dash_stat(compared, "visits").change).to eq(300)
    end

    it "leaves the change nil when there is nothing to compare against" do
      expect(stats.map(&:change).uniq).to eq([ nil ])
      expect(stats.map(&:comparison_value).uniq).to eq([ nil ])
    end

    it "reports a fall as a negative change" do
      quiet = dash_day_range(2026, 8, 9)
      fell = described_class.call(
        scope: dash_scope(range: quiet),
        comparison_scope: dash_scope(range: range)
      )

      expect(dash_stat(fell, "visits").change).to eq(-75)
      expect(dash_stat(fell, "visitors").change).to be_within(1).of(-66.67)
    end

    it "leaves the change nil rather than infinite when the comparison is zero" do
      empty = dash_scope(range: dash_day_range(2026, 8, 1))
      grew = described_class.call(scope: dash_scope(range: range), comparison_scope: empty)

      expect(dash_stat(grew, "visitors").change).to be_nil
      expect(dash_stat(grew, "visitors").comparison_value).to eq(0)
    end

    it "leaves the change nil when both sides are zero" do
      empty = dash_scope(range: dash_day_range(2026, 8, 1))
      flat = described_class.call(scope: empty, comparison_scope: empty)

      expect(flat.map(&:change).uniq).to eq([ nil ])
    end
  end
end
