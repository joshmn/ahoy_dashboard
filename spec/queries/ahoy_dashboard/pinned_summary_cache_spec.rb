# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Pinned summary cache reuse" do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    travel_to(now) { example.run }
  ensure
    Rails.cache = original_cache
  end

  before do
    [-2.days, -1.day, -1.hour].each_with_index do |offset, index|
      visit = dash_visit(started_at: now + offset, visitor: "reader-#{index % 2}", country: index.even? ? "US" : "CA")
      dash_page_view(visit, path: index.even? ? "/first" : "/second")
    end
  end

  def form(params = {})
    AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"}.merge(params))
  end

  def summary(query = form)
    AhoyDashboard::TopStatsQuery.with_series(scope: query.scope, metric: query.metric,
      comparison_scope: query.comparison_scope, interval: query.interval)
  end

  def counted(query = form)
    AhoyDashboard::TimeseriesQuery.with_total(scope: query.scope, metric: query.metric, interval: query.interval)
  end

  def aggregate_count
    statements = []
    subscriber = lambda do |*, payload|
      statements << true if !payload[:cached] && payload[:sql].include?("grouping sets")
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      AhoyDashboard.visit.uncached { yield }
    end
    statements.size
  end

  it "reuses a fresh headline without another current-range aggregate" do
    summary

    expect(aggregate_count { counted }).to eq(0)
  end

  it "preserves distinct visitors across daily buckets" do
    summary
    cached = counted
    Rails.cache.clear

    expect(cached).to eq(counted)
  end

  it "preserves page-filtered session membership" do
    query = form(filters: [{dimension: "page", operator: "is", value: "/first"}])
    summary(query)
    cached = counted(query)
    Rails.cache.clear

    expect(cached).to eq(counted(query))
  end

  [
    {period: "day"},
    {interval: "week"},
    {metric: "visits"},
    {metric: "pageviews"},
    {filters: [{dimension: "country", operator: "is", value: "US"}]},
    {crawlers: "1"},
    {internal: "1"}
  ].each do |params|
    it "does not reuse a different #{params.keys.first} count" do
      summary

      expect(aggregate_count { counted(form(params)) }).to eq(1)
    end
  end

  it "does not reuse a headline prepared in another host visit scope" do
    AhoyDashboard.visit.where(country: "US").scoping { summary }

    expect(counted.total).to eq(2)
  end

  it "does not publish raw session counts over a custom host event scope" do
    AhoyDashboard.event.where("ahoy_events.properties ->> 'path' = '/first'").scoping do
      summary

      expect(counted.total).to eq(1)
    end
  end

  it "does not extend count expiry when the headline is read from cache" do
    summary
    travel_to(now + 29.seconds)
    summary
    visit = dash_visit(started_at: now, visitor: "new-reader")
    dash_page_view(visit, path: "/new")
    travel_to(now + 31.seconds)

    expect(counted.total).to eq(3)
  end

  it "keeps a pinned card's previous-period comparison independent" do
    previous = dash_visit(started_at: now - 40.days, visitor: "previous-reader")
    dash_page_view(previous, path: "/previous")
    saved = create(:dash_saved_query, pinned: false, params: {period: "30d", filters: "none"})
    summary(form(comparison: "year_over_year"))
    cached = AhoyDashboard::PinnedQuestionsQuery.call(questions: [saved])
    Rails.cache.clear

    expect(cached).to eq(AhoyDashboard::PinnedQuestionsQuery.call(questions: [saved]))
  end
end
