require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleKeyword do
  let(:date) { Date.new(2026, 8, 10) }
  let(:keyword) do
    { date: date, query: "federal prison camp rules", clicks: 12, impressions: 400, ctr: 0.03, position: 8.4 }
  end

  describe ".absorb" do
    it "writes nothing for an empty batch" do
      expect(described_class.absorb([])).to eq(0)
      expect(described_class.count).to eq(0)
    end

    it "keeps one row per query per day and rewrites it on a re-run" do
      described_class.absorb([ keyword ])
      described_class.absorb([ keyword.merge(clicks: 19, position: 6.1) ])

      expect(described_class.count).to eq(1)
      expect(sole_item(described_class).clicks).to eq(19)
      expect(sole_item(described_class).position).to be_within(0.001).of(6.1)
    end

    it "keeps the same query on two days apart, which is the whole point" do
      described_class.absorb([ keyword, keyword.merge(date: date - 1, position: 11.0) ])

      expect(described_class.order(:date).pluck(:position)).to eq([ 11.0, 8.4 ])
    end

    it "drops a query too long for the index rather than losing the batch" do
      long = keyword.merge(query: "a" * (described_class::KEY_BUDGET + 1))

      expect(described_class.absorb([ long, keyword ])).to eq(1)
      expect(described_class.pluck(:query)).to eq([ keyword[:query] ])
    end

    it "names the query and its size in the log" do
      allow(Rails.logger).to receive(:warn)

      described_class.absorb([ keyword.merge(query: "a" * (described_class::KEY_BUDGET + 1)) ])

      expect(Rails.logger).to have_received(:warn).with(
        "search console keyword dropped for #{date}, query is 2501 bytes and the index holds 2500: #{"a" * 57}..."
      )
    end

    it "writes nothing when every row is over budget" do
      expect(described_class.absorb([ keyword.merge(query: "a" * (described_class::KEY_BUDGET + 1)) ])).to eq(0)
    end
  end

  it "windows by date" do
    described_class.absorb([ keyword, keyword.merge(date: Date.new(2026, 7, 1)) ])
    range = Date.new(2026, 8, 1).beginning_of_day..Date.new(2026, 8, 31).end_of_day

    expect(described_class.in_range(range).pluck(:date)).to eq([ date ])
  end

  it "is expected to exceed the sum of the query x page rows for the same query" do
    described_class.absorb([ keyword ])
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: date, query: keyword[:query], page: "https://x/1", clicks: 5, impressions: 150,
        ctr: 0.03, position: 8.0 }
    ])

    expect(sole_item(described_class).clicks).to be > AhoyDashboard::SearchConsoleRow.where(query: keyword[:query]).sum(:clicks)
  end
end
