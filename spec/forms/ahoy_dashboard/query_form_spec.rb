# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::QueryForm do
  let(:now) { Time.utc(2026, 8, 11, 14, 30, 17) }

  around { |example| travel_to(now) { example.run } }

  it "accepts string keys from a nested URL without changing filter groups" do
    form = described_class.from_params({ "period" => "7d", "filters" => [
      { "dimension" => "country", "operator" => "is", "value" => "US", "group" => "0" },
      { "dimension" => "country", "operator" => "is", "value" => "CA", "group" => "0" }
    ] })

    expect(form.filters.groups.map { |group| group.map(&:value) }).to eq([["US", "CA"]])
  end

  it "restores a string-keyed view when the URL does not specify a range" do
    form = described_class.from_params({}, remembered: "period=7d&metric=visits")

    expect(form.to_query).to include(period: "7d", metric: "visits")
  end

  it "accepts unpermitted controller parameters at its input boundary" do
    form = described_class.from_params(ActionController::Parameters.new(period: "7d", metric: "visits"))

    expect(form.to_query).to include(period: "7d", metric: "visits")
  end

  it "aligns a running named comparison to the analytical freshness boundary" do
    form = described_class.from_params({ period: "day", comparison: "previous_period" })

    expect(form.comparison_range.end).to eq((now - 1.day).change(sec: 0))
  end

  it "keeps completed named comparison ranges exact" do
    form = described_class.from_params({ period: "yesterday", comparison: "previous_period" })

    expect(form.comparison_range).to eq((now - 2.days).all_day)
  end

  it "keeps explicit historical custom comparison ranges exact" do
    form = described_class.from_params({ period: "custom", from: "2026-08-01T10:15", to: "2026-08-01T11:45",
      comparison: "previous_period" })

    expect(form.comparison_range).to eq(form.period.comparison_range(form.range, :previous_period, now: now))
  end

  it "keeps explicit running custom comparison ranges exact" do
    form = described_class.from_params({ period: "custom", from: "2026-08-11T10:15", to: "2026-08-11T23:45",
      comparison: "previous_period" })

    expect(form.comparison_range).to eq(form.period.comparison_range(form.range, :previous_period, now: now))
  end
end
