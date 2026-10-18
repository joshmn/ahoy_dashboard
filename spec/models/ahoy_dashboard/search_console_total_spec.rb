require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleTotal do
  let(:total) do
    { date: Date.new(2026, 8, 10), clicks: 400, impressions: 9_000, ctr: 0.044, position: 11.2 }
  end

  describe ".absorb" do
    it "writes nothing for an empty batch" do
      expect(described_class.absorb([])).to eq(0)
      expect(described_class.count).to eq(0)
    end

    it "keeps one row per day and rewrites it on a re-run" do
      described_class.absorb([ total ])
      described_class.absorb([ total.merge(clicks: 450) ])

      expect(described_class.count).to eq(1)
      expect(described_class.first.clicks).to eq(450)
    end
  end

  it "is expected to exceed the sum of the query rows" do
    described_class.absorb([ total ])
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: total[:date], query: "a", page: "https://x/1", clicks: 120, impressions: 3_000, ctr: 0.04, position: 9.0 },
      { date: total[:date], query: "b", page: "https://x/2", clicks: 80, impressions: 2_000, ctr: 0.04, position: 14.0 }
    ])

    range = total[:date].beginning_of_day..total[:date].end_of_day
    named = AhoyDashboard::SearchConsoleRow.in_range(range).sum(:clicks)

    expect(described_class.in_range(range).sum(:clicks)).to be > named
  end

  it "windows by date" do
    described_class.absorb([ total, total.merge(date: Date.new(2026, 7, 1), clicks: 10) ])
    range = Date.new(2026, 8, 1).beginning_of_day..Date.new(2026, 8, 31).end_of_day

    expect(described_class.in_range(range).pluck(:clicks)).to eq([ 400 ])
  end
end
