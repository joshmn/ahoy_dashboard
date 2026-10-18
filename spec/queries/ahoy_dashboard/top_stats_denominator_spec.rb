# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Top stat visitor denominators" do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  include_context "with a memory cache"

  before do
    first = dash_landing("/a", at: range.begin + 1.hour, visitor: "returning")
    dash_goal(first, "purchased")
    dash_landing("/b", at: range.begin + 2.hours, visitor: "returning")
    bot = dash_visit(started_at: range.begin + 3.hours, visitor: "crawler")
    dash_page_view(bot, path: "/a", crawler: "GPTBot")
    dash_visit(started_at: range.begin + 4.hours, visitor: "without events")
    dash_landing("/a", at: range.begin + 5.hours, visitor_token: nil)
    create(:dash_goal, event_name: "purchased")
  end

  it "reuses the header visitor total without another database count" do
    AhoyDashboard::TopStatsQuery.with_series(scope: scope, metric: "visitors")
    expect(captured_sql(cached: true) { scope.total_visitors }).to be_empty
  end

  [
    {},
    { include_crawlers: true },
    { filter: ["page", "is", "/b"] },
    { filter: ["goal", "is", "purchased"] }
  ].each do |options|
    it "preserves the scoped denominator for #{options.inspect}" do
      filters = options[:filter] ? dash_filters(options[:filter]) : AhoyDashboard::Filters.new([])
      target = dash_scope(range: range, include_crawlers: options[:include_crawlers] || false, filters: filters)
      expected = target.visits.distinct.count(:visitor_token)
      AhoyDashboard::TopStatsQuery.call(scope: target)

      expect(target.total_visitors).to eq(expected)
    end
  end

  it "does not extend the denominator lifetime when header aggregates come from cache" do
    AhoyDashboard::TopStatsQuery.with_series(scope: scope, metric: "visitors")
    travel(20.seconds)
    AhoyDashboard::TopStatsQuery.with_series(scope: scope, metric: "visitors")
    dash_landing("/c", at: range.begin + 6.hours, visitor: "additional")
    travel(11.seconds)

    expect(scope.total_visitors).to eq(2)
  end

  it "does not replace the denominator with a metric that omitted visitors" do
    AhoyDashboard::TopStatsQuery.call(scope: scope, metrics: ["bounce_rate"])

    expect(scope.total_visitors).to eq(1)
  end
end
