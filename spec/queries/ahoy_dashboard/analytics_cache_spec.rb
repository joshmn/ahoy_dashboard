# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::AnalyticsCache do
  let(:now) { Time.utc(2026, 8, 11, 14, 30, 5) }
  let(:range) { now.beginning_of_day..now.end_of_day }

  include_context "with a memory cache"

  around { |example| travel_to(now) { example.run } }

  def visitor(country: "US", token: nil, at: now - 1.hour)
    dash_landing(at: at, country: country, visitor: token)
  end

  def total(scope: dash_scope(range: range), metric: "visitors")
    AhoyDashboard::TopStatsQuery.call(scope: scope, metrics: [metric]).first.value
  end

  def series(metric: "visitors", interval: :day, scope: dash_scope(range: range))
    AhoyDashboard::TimeseriesQuery.call(scope: scope, metric: metric, interval: interval)
  end

  it "reuses a headline aggregate for thirty seconds" do
    visitor
    total
    visitor

    expect(total).to eq(1)
  end

  it "refreshes headline aggregates after expiry" do
    visitor
    total
    visitor
    travel(31.seconds)

    expect(total).to eq(2)
  end

  it "isolates filter predicates" do
    visitor(country: "US")
    2.times { visitor(country: "CA") }
    total(scope: dash_scope(range: range, filters: dash_filters(["country", "is", "US"])))

    expect(total(scope: dash_scope(range: range, filters: dash_filters(["country", "is", "CA"])))).to eq(2)
  end

  it "isolates date ranges" do
    visitor
    total

    expect(total(scope: dash_scope(range: (now - 1.day).all_day))).to eq(0)
  end

  it "isolates session counts from distinct visitor counts" do
    2.times { visitor(token: "returning") }
    total

    expect(total(metric: "visits")).to eq(2)
  end

  it "reclassifies internal traffic immediately when the site host changes" do
    visit = visitor
    visit.update!(referring_domain: "first.example")
    AhoyDashboard::Preferences.write(:site, host: "first.example")
    filters = dash_filters(["channel", "is", AhoyDashboard::Sql::INTERNAL])
    total(scope: dash_scope(range: range, filters: filters))
    AhoyDashboard::Preferences.write(:site, host: "second.example")

    expect(total(scope: dash_scope(range: range, filters: filters))).to eq(0)
  end

  it "reuses raw chart counts" do
    visitor
    series
    visitor

    expect(series.map(&:last).sum).to eq(1)
  end

  it "isolates chart metrics" do
    2.times { visitor(token: "returning") }
    series

    expect(series(metric: "visits").map(&:last).sum).to eq(2)
  end

  it "isolates bucket intervals" do
    visitor
    series

    expect(series(interval: :hour).length).to eq(24)
  end

  it "isolates bucket time zones" do
    visitor(at: range.begin + 1.hour)
    AhoyDashboard::Preferences.write(:site, time_zone: "UTC")
    series
    AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago")

    expect(series.find { |_time, value| value == 1 }.first.to_date).to eq(Date.new(2026, 8, 10))
  end

  it "reuses combined headline and chart aggregates" do
    visitor
    AhoyDashboard::TopStatsQuery.with_series(scope: dash_scope(range: range), metric: "visitors")
    visitor
    result = AhoyDashboard::TopStatsQuery.with_series(scope: dash_scope(range: range), metric: "visitors")

    expect([result.stats.first.value, result.series.map(&:last).sum]).to eq([1, 1])
  end

  it "reuses pinned count readings without caching the question label" do
    visitor
    question = create(:dash_saved_query, name: "Original", pinned: true, params: { "period" => "day", "metric" => "visitors" })
    AhoyDashboard::PinnedQuestionsQuery.call(questions: [question])
    visitor
    question.update!(name: "Renamed")
    reading = AhoyDashboard::PinnedQuestionsQuery.call(questions: [question]).first
    card = AhoyDashboard::PinnedQuestionPresenter.new(reading: reading)

    expect([card.name, card.display]).to eq(["Renamed", "1"])
  end

  it "reuses ongoing comparison readings within the same thirty second boundary" do
    visitor(at: now - 1.day - 1.minute)
    form = AhoyDashboard::QueryForm.from_params({ period: "day", comparison: "previous_period" })
    total(scope: form.comparison_scope)
    visitor(at: now - 1.day - 2.minutes)
    travel(10.seconds)
    current = AhoyDashboard::QueryForm.from_params({ period: "day", comparison: "previous_period" })

    expect(total(scope: current.comparison_scope)).to eq(1)
  end

  it "advances the comparison boundary and its cached reading together" do
    visitor(at: now - 1.day - 1.minute)
    form = AhoyDashboard::QueryForm.from_params({ period: "day", comparison: "previous_period" })
    total(scope: form.comparison_scope)
    visitor(at: now - 1.day + 10.seconds)
    travel(31.seconds)
    current = AhoyDashboard::QueryForm.from_params({ period: "day", comparison: "previous_period" })

    expect(total(scope: current.comparison_scope)).to eq(2)
  end

  it "reuses default rolling exclusion previews within the same thirty second boundary" do
    filters = [dash_filters(["country", "is", "US"])]
    visitor
    AhoyDashboard::ExclusionCountsQuery.call(filters: filters)
    visitor
    travel(10.seconds)

    expect(AhoyDashboard::ExclusionCountsQuery.call(filters: filters)).to eq([1])
  end

  it "keeps cached exclusion counts intact after reading them" do
    visitor
    filters = [dash_filters(["country", "is", "US"])]
    2.times { AhoyDashboard::ExclusionCountsQuery.call(filters: filters, floor: range.begin) }

    expect(AhoyDashboard::ExclusionCountsQuery.call(filters: filters, floor: range.begin)).to eq([1])
  end

  it "preserves exact explicit exclusion preview boundaries" do
    visitor(at: range.begin)
    filters = [dash_filters(["country", "is", "US"])]
    AhoyDashboard::ExclusionCountsQuery.call(filters: filters, floor: range.begin)

    expect(AhoyDashboard::ExclusionCountsQuery.call(filters: filters, floor: range.begin + 1.second)).to eq([0])
  end

  it "isolates schemas when the host changes its connection search path" do
    connection = AhoyDashboard.visit.connection
    original_path = connection.schema_search_path
    connection.schema_search_path = "public"
    described_class.fetch(key: "schema", connection: connection) { connection.select_value("select current_schema()") }
    connection.schema_search_path = "pg_catalog"

    expect(described_class.fetch(key: "schema", connection: connection) { connection.select_value("select current_schema()") }).to eq("pg_catalog")
  ensure
    connection.schema_search_path = original_path
  end

  it "recomputes aggregates when the host uses NullStore" do
    Rails.cache = ActiveSupport::Cache::NullStore.new
    visitor
    total
    visitor

    expect(total).to eq(2)
  end
end
