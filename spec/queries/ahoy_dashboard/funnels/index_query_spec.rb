# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Funnels::IndexQuery do
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "7d" }) }
  let(:goals) { create_list(:dash_goal, 2) }
  let!(:funnels) { Array.new(6) { |index| create(:dash_funnel, position: index + 1, goals: goals) } }

  it "only executes funnel aggregates for the displayed page" do
    statements = captured_sql(/with tm_funnel as materialized/i, cached: true) do
      described_class.call(query: query, page: 1)
    end

    expect(statements.length).to eq(4)
  end

  it "clamps an out-of-range page to the last available page" do
    result = described_class.call(query: query, page: "999999")

    expect(result.readings.map(&:funnel)).to eq(funnels.last(2))
  end

  it "treats an invalid page as the first page" do
    result = described_class.call(query: query, page: "invalid")

    expect(result.readings.map(&:funnel)).to eq(funnels.first(4))
  end

  context "without configured funnels" do
    let!(:funnels) { [] }

    it "keeps the empty collection on page one" do
      result = described_class.call(query: query, page: 2)

      expect([result.total, result.page, result.pages]).to eq([0, 1, 1])
    end
  end
end
