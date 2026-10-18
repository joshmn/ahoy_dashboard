# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cached analytics" do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }
  let(:country) { AhoyDashboard::Dimension.find("country") }

  include_context "with a memory cache"

  def visit(country:, visitor:)
    dash_landing("/#{country}", at: range.begin + 1.hour, country: country, visitor: visitor)
  end

  def countries
    AhoyDashboard::FilterOptionsQuery.for_dimensions(
      scope: scope, dimensions: [country, AhoyDashboard::Dimension.find("browser")]
    ).fetch("country")
  end

  it "keeps a filter option snapshot for the existing freshness window" do
    visit(country: "US", visitor: "one")
    countries
    visit(country: "CA", visitor: "two")

    expect(countries).to eq(["US"])
  end

  it "refreshes filter options after the freshness window expires" do
    visit(country: "US", visitor: "one")
    countries
    visit(country: "CA", visitor: "two")
    travel(AhoyDashboard::ScopeQuery::TOTAL_TTL + 1.second)

    expect(countries).to contain_exactly("US", "CA")
  end

  it "keeps a cached pagination count intact when the report reads its rows again" do
    visit(country: "US", visitor: "one")
    visit(country: "CA", visitor: "two")
    query = { scope: scope, dimension: country, limit: 1 }
    AhoyDashboard::BreakdownQuery.with_row_count(**query)

    expect(AhoyDashboard::BreakdownQuery.with_row_count(**query).row_count).to eq(2)
  end

  it "reads exports from current data instead of caching an unbounded result" do
    visit(country: "US", visitor: "one")
    query = { scope: scope, dimension: country, limit: nil }
    AhoyDashboard::BreakdownQuery.call(**query)
    visit(country: "CA", visitor: "two")

    expect(AhoyDashboard::BreakdownQuery.call(**query).rows.map(&:value)).to contain_exactly("US", "CA")
  end

  context "goal conversions" do
    let!(:goal) { create(:dash_goal, event_name: "purchased") }
    let!(:visitor) { dash_visit(started_at: range.begin + 1.hour, visitor: "buyer") }

    before do
      dash_page_view(visitor, path: "/checkout")
      dash_goal(visitor, "purchased", at: range.begin + 2.hours)
      AhoyDashboard::GoalsQuery.call(scope: scope)
      dash_goal(visitor, "purchased", at: range.begin + 3.hours)
    end

    it "keeps bounded goal counts within the analytical freshness window" do
      expect(AhoyDashboard::GoalsQuery.call(scope: scope).rows.first.metrics["events"]).to eq(1)
    end

    it "refreshes goal counts after the analytical freshness window" do
      travel(AhoyDashboard::ScopeQuery::TOTAL_TTL + 1.second)

      expect(AhoyDashboard::GoalsQuery.call(scope: scope).rows.first.metrics["events"]).to eq(2)
    end

    it "reads current goal counts for an export" do
      expect(AhoyDashboard::GoalsQuery.call(scope: scope, limit: nil).rows.first.metrics["events"]).to eq(2)
    end

    it "applies updated goal definitions immediately" do
      goal.update!(event_name: "signed_up")

      expect(AhoyDashboard::GoalsQuery.call(scope: scope).rows.first.metrics["events"]).to eq(0)
    end
  end
end
