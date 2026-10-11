require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::TimeseriesQuery do
  let(:range) { dash_time(2026, 8, 8)..dash_time(2026, 8, 11).end_of_day }
  let(:scope) { dash_scope(range: range) }

  def series(metric, interval: :day, on: scope)
    described_class.call(scope: on, metric: AhoyDashboard::Metric.find(metric), interval: interval)
  end

  def by_date(points)
    points.map { |at, value| [ at.in_time_zone(AhoyDashboard.time_zone).to_date, value ] }.to_h
  end

  it "returns one bucket per day in the range, empties included" do
    points = series("visits")

    expect(points.map(&:first).map { |at| at.in_time_zone(AhoyDashboard.time_zone).to_date }).to eq(
      [ Date.new(2026, 8, 8), Date.new(2026, 8, 9), Date.new(2026, 8, 10), Date.new(2026, 8, 11) ]
    )
    expect(points.map(&:last)).to eq([ 0, 0, 0, 0 ])
  end

  it "hands the buckets back in ascending order" do
    dash_page_view(dash_visit(started_at: dash_time(2026, 8, 9, 12)))

    points = series("visits")

    expect(points.map(&:first)).to eq(points.map(&:first).sort)
  end

  # An 11pm visit in Chicago is 4am the next day in UTC. Bucketing in UTC moves
  # it a whole day and every daily total on the chart is wrong by one evening.
  describe "the day boundary" do
    before do
      late = dash_visit(started_at: dash_time(2026, 8, 10, 23, 0), visitor: "late")
      dash_page_view(late, path: "/a", at: dash_time(2026, 8, 10, 23, 30))
    end

    it "buckets a visit that started at eleven at night on the day it started, locally" do
      expect(by_date(series("visits"))).to eq(
        Date.new(2026, 8, 8) => 0, Date.new(2026, 8, 9) => 0,
        Date.new(2026, 8, 10) => 1, Date.new(2026, 8, 11) => 0
      )
    end

    it "buckets an eleven thirty pageview on the same local day" do
      expect(by_date(series("pageviews"))).to eq(
        Date.new(2026, 8, 8) => 0, Date.new(2026, 8, 9) => 0,
        Date.new(2026, 8, 10) => 1, Date.new(2026, 8, 11) => 0
      )
    end

    it "buckets unique visitors on the same local day" do
      expect(by_date(series("visitors"))).to eq(
        Date.new(2026, 8, 8) => 0, Date.new(2026, 8, 9) => 0,
        Date.new(2026, 8, 10) => 1, Date.new(2026, 8, 11) => 0
      )
    end
  end

  describe "counts" do
    before do
      first = dash_visit(started_at: dash_time(2026, 8, 9, 9), visitor: "a")
      dash_page_view(first, path: "/a", at: dash_time(2026, 8, 9, 9))
      dash_page_view(first, path: "/b", at: dash_time(2026, 8, 9, 9, 5))

      second = dash_visit(started_at: dash_time(2026, 8, 9, 14), visitor: "a")
      dash_page_view(second, path: "/a", at: dash_time(2026, 8, 9, 14))

      third = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "b")
      dash_page_view(third, path: "/a", at: dash_time(2026, 8, 10, 9))
    end

    it "counts visits per bucket" do
      expect(by_date(series("visits")).values).to eq([ 0, 2, 1, 0 ])
    end

    it "counts unique visitors per bucket, not across the range" do
      expect(by_date(series("visitors")).values).to eq([ 0, 1, 1, 0 ])
    end

    it "counts pageviews per bucket" do
      expect(by_date(series("pageviews")).values).to eq([ 0, 3, 1, 0 ])
    end

    # An average of averages is not the average. The ninth is one bounce in two
    # visits and the tenth is one in one, which is 50 and 100, not 75.
    it "computes a bounce rate per bucket rather than averaging the buckets" do
      values = by_date(series("bounce_rate")).values

      expect(values[1]).to be_within(0.001).of(50.0)
      expect(values[2]).to be_within(0.001).of(100.0)
      expect(values[0]).to eq(0)
      expect(values[3]).to eq(0)
    end

    it "keeps a session with no page view out of the bucket's bounce rate" do
      searched = dash_visit(started_at: dash_time(2026, 8, 10, 15), visitor: "c")
      dash_goal(searched, "site_searched", at: dash_time(2026, 8, 10, 15))

      expect(by_date(series("visits")).values).to eq([ 0, 2, 2, 0 ])
      expect(by_date(series("bounce_rate")).values[2]).to be_within(0.001).of(100.0)
    end

    it "computes views per visit per bucket" do
      values = by_date(series("views_per_visit")).values

      expect(values[1]).to be_within(0.001).of(1.5)
      expect(values[2]).to be_within(0.001).of(1.0)
      expect(values[0]).to eq(0)
    end

    it "computes visit duration per bucket" do
      values = by_date(series("visit_duration")).values

      expect(values[1]).to be_within(0.001).of(150.0)
      expect(values[2]).to be_within(0.001).of(0.0)
    end


  end

  describe "scroll depth" do
    before do
      ninth = dash_visit(started_at: dash_time(2026, 8, 9, 9), visitor: "a")
      dash_page_view(ninth, path: "/a", at: dash_time(2026, 8, 9, 9))
      engagement(ninth, depth: 20, at: dash_time(2026, 8, 9, 9, 1))
      engagement(ninth, depth: 60, at: dash_time(2026, 8, 9, 9, 2))

      tenth = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "b")
      dash_page_view(tenth, path: "/a", at: dash_time(2026, 8, 10, 9))
      engagement(tenth, depth: 90, at: dash_time(2026, 8, 10, 9, 1))
    end

    def engagement(visit, depth:, at:, path: "/a")
      dash_goal(visit, AhoyDashboard::ENGAGEMENT, at: at, path: path, scroll_depth: depth)
    end

    # Two page views read to 20 and 60 is a bucket that averages 40. Averaging
    # the ninth's 40 against the tenth's 90 across buckets would say 65 for a day
    # nobody spent on the site.
    it "averages the depth inside each bucket rather than across them" do
      values = by_date(series("scroll_depth")).values

      expect(values[1]).to be_within(0.001).of(40.0)
      expect(values[2]).to be_within(0.001).of(90.0)
    end

    it "draws a zero rather than a gap on a day nothing was reported" do
      expect(by_date(series("scroll_depth")).values).to eq([ 0.0, 40.0, 90.0, 0.0 ])
    end

    it "reads past a depth the client never should have sent" do
      junk = dash_visit(started_at: dash_time(2026, 8, 11, 9), visitor: "c")
      dash_page_view(junk, path: "/a", at: dash_time(2026, 8, 11, 9))
      engagement(junk, depth: "most", at: dash_time(2026, 8, 11, 9, 1))

      expect(by_date(series("scroll_depth")).values).to eq([ 0.0, 40.0, 90.0, 0.0 ])
    end
  end

  # A visit that started inside the range can own an event outside it. Left
  # alone groupdate drops that row and the chart stops adding up to the strip.
  it "keeps every pageview of an in range visit on the chart" do
    late = dash_visit(started_at: dash_time(2026, 8, 11, 23, 45))
    dash_page_view(late, path: "/a", at: dash_time(2026, 8, 11, 23, 45))
    dash_page_view(late, path: "/b", at: dash_time(2026, 8, 12, 0, 10))

    expect(series("pageviews").sum(&:last)).to eq(scope.pageviews.count)
  end

  it "buckets by hour when asked" do
    dash_page_view(dash_visit(started_at: dash_time(2026, 8, 11, 13, 20)))

    points = series("visits", interval: :hour, on: dash_scope(range: dash_day_range(2026, 8, 11)))

    expect(points.size).to eq(24)
    expect(points.map(&:last).sum).to eq(1)
    expect(points.find { |at, _| at.in_time_zone(AhoyDashboard.time_zone).hour == 13 }.last).to eq(1)
  end

  it "buckets by month when asked" do
    dash_page_view(dash_visit(started_at: dash_time(2026, 7, 4, 10)))
    dash_page_view(dash_visit(started_at: dash_time(2026, 8, 4, 10)))

    wide = dash_scope(range: dash_time(2026, 6, 1)..dash_time(2026, 8, 31).end_of_day)
    points = described_class.call(scope: wide, metric: AhoyDashboard::Metric.find("visits"), interval: :month)

    expect(points.map(&:last)).to eq([ 0, 1, 1 ])
  end

  it "draws a flat zero line against an empty database" do
    expect(series("visitors").map(&:last)).to eq([ 0, 0, 0, 0 ])
    expect(series("bounce_rate").map(&:last)).to eq([ 0, 0, 0, 0 ])
    expect(series("visit_duration").map(&:last)).to eq([ 0, 0, 0, 0 ])
  end
end
