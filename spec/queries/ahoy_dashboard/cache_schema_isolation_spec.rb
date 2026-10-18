# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Analytics cache schema isolation" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:tables) do
    %w[ahoy_visits ahoy_events ahoy_dashboard_search_console_rows ahoy_dashboard_search_console_keywords
       ahoy_dashboard_search_console_totals ahoy_dashboard_search_console_days]
  end

  around do |example|
    original_path = connection.schema_search_path
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    %w[first second].each do |name|
      connection.execute("CREATE SCHEMA dashboard_cache_#{name}")
      tables.each do |table|
        connection.execute("CREATE TABLE dashboard_cache_#{name}.#{table} (LIKE public.#{table} INCLUDING ALL)")
      end
    end
    example.run
  ensure
    connection.schema_search_path = original_path
    connection.schema_cache.clear!
    Rails.cache = original_cache
    AhoyDashboard::Current.reset
  end

  before do
    seed("first", "one", 1)
    seed("second", "two", 2)
  end

  def switch(name)
    connection.schema_search_path = "dashboard_cache_#{name}, public"
    connection.schema_cache.clear!
    AhoyDashboard::Current.reset
  end

  def seed(schema, label, count)
    switch(schema)
    count.times do |index|
      visit = dash_visit(started_at: range.begin + 1.hour, visitor: "visitor-#{index}",
                         landing_page: "https://example.com/facet/#{label}")
      dash_page_view(visit, path: "/facet/#{label}")
      dash_goal(visit, label, "custom_#{label}" => "value")
    end
    create(:dash_search_console_row, date: range.begin.to_date, query: label, clicks: count)
    create(:dash_search_console_keyword, date: range.begin.to_date, query: label, clicks: count)
    create(:dash_search_console_total, date: range.begin.to_date, clicks: count)
    create(:dash_search_console_day, date: range.begin.to_date, scanned_at: range.begin)
  end

  def scope
    dash_scope(range: range)
  end

  def warm_other_schema
    switch("first")
    yield
    switch("second")
  end

  it "keeps visitor denominators within the active schema" do
    warm_other_schema { scope.total_visitors }

    expect(scope.total_visitors).to eq(2)
  end

  it "keeps discovered event names within the active schema" do
    warm_other_schema { AhoyDashboard::EventNamesQuery.call(scope: scope) }

    expect(AhoyDashboard::EventNamesQuery.call(scope: scope)).to eq(["two"])
  end

  it "keeps discovered property keys within the active schema" do
    warm_other_schema { AhoyDashboard::PropertyKeysQuery.call(scope: scope) }

    expect(AhoyDashboard::PropertyKeysQuery.call(scope: scope)).to eq(["custom_two"])
  end

  it "keeps facet search values within the active schema" do
    warm_other_schema { AhoyDashboard::FacetSearchQuery.call(scope: scope, term: "facet") }
    groups = AhoyDashboard::FacetSearchQuery.call(scope: scope, term: "facet")

    expect(groups.find { |group| group.key == "page" }.values.map(&:label)).to eq(["/facet/two"])
  end

  it "keeps stored Search Console rows within the active schema" do
    warm_other_schema { AhoyDashboard::SearchConsoleStoredQuery.new(range: range, limit: 9, account: nil).call }
    reading = AhoyDashboard::SearchConsoleStoredQuery.new(range: range, limit: 9, account: nil).call

    expect(reading.fetch(:top).fetch(:query).map(&:first)).to eq(["two"])
  end
end
