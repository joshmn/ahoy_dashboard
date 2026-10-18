# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pinned headline reuse" do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before do
    [-2.days, -1.day, -1.hour, 0].each_with_index do |offset, index|
      visit = dash_landing("/first", at: now + offset, visitor: "reader-#{index % 2}", country: index.even? ? "US" : "CA")
      dash_page_view(visit, path: "/second", at: now + offset + 2.hours)
    end
  end

  def headline(params = {})
    form = AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"}.merge(params))
    readings = AhoyDashboard::TopStatsQuery.with_series(scope: form.scope, metric: form.metric,
      comparison_scope: form.comparison_scope, interval: form.interval)
    AhoyDashboard::Dashboards::HeadlineReading.new(query: form, readings: readings)
  end

  def question(params = {})
    create(:dash_saved_query, pinned: false, params: {"period" => "30d", "filters" => "none"}.merge(params))
  end

  %w[visitors visits pageviews].each do |metric|
    it "preserves the #{metric} card and its independently calculated comparison" do
      saved = question("metric" => metric)
      prepared = headline(metric: metric, comparison: "year_over_year")

      expect(AhoyDashboard::PinnedQuestionsQuery.call(questions: [saved], headline: prepared))
        .to eq(AhoyDashboard::PinnedQuestionsQuery.call(questions: [saved]))
    end
  end

  it "runs only the comparison aggregate when current readings match" do
    saved = question
    prepared = headline
    statements = captured_sql(/\bFROM\s+"?ahoy_visits\b/i) do
      AhoyDashboard.visit.uncached { AhoyDashboard::PinnedQuestionsQuery.call(questions: [saved], headline: prepared) }
    end

    expect(statements.size).to eq(1)
  end

  [
    {metric: "pageviews"},
    {period: "day"},
    {interval: "week"},
    {filters: [{dimension: "country", operator: "is", value: "US"}]},
    {crawlers: "1"},
    {internal: "1"}
  ].each do |params|
    it "does not reuse a headline with different #{params.keys.first}" do
      saved = question

      expect(AhoyDashboard::PinnedQuestionsQuery.call(questions: [saved], headline: headline(params)))
        .to eq(AhoyDashboard::PinnedQuestionsQuery.call(questions: [saved]))
    end
  end

  it "rejects a changed time zone even when the named period is the same" do
    prepared = headline
    AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago")
    form = AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"})

    expect(prepared.matches?(query: form)).to eq(false)
  end

  it "rejects changed host model scopes" do
    prepared = AhoyDashboard.visit.where(country: "US").scoping { headline }
    form = AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"})

    expect(prepared.matches?(query: form)).to eq(false)
  end
end
