# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::HiddenVisitsQuery do
  let(:range) { dash_day_range(2026, 8, 10) }

  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous
  end

  before do
    AhoyDashboard::Preferences.write(:site, internal_ips: ["127.0.0.0/8"])
    dash_visit(started_at: range.begin + 1.hour, visitor: "internal", ip: "127.0.0.1")
    dash_visit(started_at: range.begin + 1.hour, visitor: "reader", ip: "8.8.8.8")
  end

  it "counts hidden visits inside the requested range" do
    dash_visit(started_at: range.begin - 1.day, visitor: "earlier", ip: "127.0.0.1")

    expect(described_class.call(range: range)).to eq(1)
  end

  it "keeps a reading for the analytical freshness window" do
    described_class.call(range: range)
    dash_visit(started_at: range.begin + 2.hours, visitor: "later", ip: "127.0.0.2")

    expect(described_class.call(range: range)).to eq(1)
  end

  it "refreshes after the analytical freshness window expires" do
    described_class.call(range: range)
    dash_visit(started_at: range.begin + 2.hours, visitor: "later", ip: "127.0.0.2")
    travel(AhoyDashboard::ScopeQuery::TOTAL_TTL + 1.second)

    expect(described_class.call(range: range)).to eq(2)
  end

  it "applies changed exclusions immediately" do
    described_class.call(range: range)
    AhoyDashboard::Preferences.write(:site, internal_ips: ["10.0.0.0/8"])

    expect(described_class.call(range: range)).to eq(0)
  end

  it "returns zero when exclusions are disabled" do
    described_class.call(range: range)
    AhoyDashboard::Preferences.write(:site, internal_ips: [])

    expect(described_class.call(range: range)).to eq(0)
  end
end
