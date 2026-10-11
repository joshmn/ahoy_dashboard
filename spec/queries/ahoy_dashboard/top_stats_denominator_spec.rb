# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Top stat visitor denominators" do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous
  end

  before do
    first = dash_visit(started_at: range.begin + 1.hour, visitor: "returning")
    dash_page_view(first, path: "/a")
    dash_goal(first, "purchased")
    returning = dash_visit(started_at: range.begin + 2.hours, visitor: "returning")
    dash_page_view(returning, path: "/b")
    bot = dash_visit(started_at: range.begin + 3.hours, visitor: "crawler")
    dash_page_view(bot, path: "/a", crawler: "GPTBot")
    dash_visit(started_at: range.begin + 4.hours, visitor: "without events")
    anonymous = dash_visit(started_at: range.begin + 5.hours, visitor_token: nil)
    dash_page_view(anonymous, path: "/a")
    AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "purchased")
  end

  it "reuses the header visitor total without another database count" do
    AhoyDashboard::TopStatsQuery.with_series(scope: scope, metric: "visitors")
    statements = []
    capture = ->(*args) { statements << args.last[:sql] unless args.last[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { scope.total_visitors }

    expect(statements).to be_empty
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
    additional = dash_visit(started_at: range.begin + 6.hours, visitor: "additional")
    dash_page_view(additional, path: "/c")
    travel(11.seconds)

    expect(scope.total_visitors).to eq(2)
  end

  it "does not replace the denominator with a metric that omitted visitors" do
    AhoyDashboard::TopStatsQuery.call(scope: scope, metrics: ["bounce_rate"])

    expect(scope.total_visitors).to eq(1)
  end
end
