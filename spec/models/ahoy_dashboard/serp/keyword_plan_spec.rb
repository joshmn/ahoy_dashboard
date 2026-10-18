require "rails_helper"

RSpec.describe AhoyDashboard::Serp::KeywordPlan do
  let(:adapter) { AhoyDashboard::Serp::Adapters::SerpApiAdapter }

  def plan(pages: 2, place_count: 3, frequency: "weekly")
    described_class.new(pages: pages, place_count: place_count, frequency: frequency)
  end

  it "prices one check as the provider's units for the depth, once per place" do
    expect(plan.per_check(adapter)).to eq(adapter.cost_units(pages: 2) * 3)
  end

  it "rounds a month of checks up rather than promising a fraction of one" do
    expect(plan(frequency: "weekly").monthly_checks).to eq((3 * 2 * (30.0 / 7)).ceil)
    expect(plan(frequency: "daily").monthly_checks).to eq(180)
  end

  it "prices a month off the same per check figure" do
    expect(plan(frequency: "daily").monthly_units(adapter)).to eq(plan.per_check(adapter) * 30)
  end

  it "costs nothing on the sample provider" do
    expect(plan.monthly_units(AhoyDashboard::Serp::Adapters::FakeAdapter)).to eq(0)
  end

  it "gives a keyword and the add form the same figures for the same plan" do
    keyword = build(:dash_serp_keyword, pages: 2, locations: %w[us gb ca], frequency: :weekly)

    expect([ keyword.cost_units(adapter), keyword.monthly_units(adapter), keyword.monthly_checks ])
      .to eq([ plan.per_check(adapter), plan.monthly_units(adapter), plan.monthly_checks ])
  end
end
