require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleKeyword do
  let(:date) { Date.new(2026, 8, 10) }
  let(:keyword) do
    { date: date, query: "federal prison camp rules", clicks: 12, impressions: 400, ctr: 0.03, position: 8.4 }
  end

  it "sits on the prefixed table" do
    expect(described_class.table_name).to eq("ahoy_dashboard_search_console_keywords")
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

    # Same rule as SearchConsoleRow: one over-budget row would take the day's
    # whole batch down, because an upsert is one statement.
    it "drops a query too long for the index rather than losing the batch" do
      long = keyword.merge(query: "a" * (described_class::KEY_BUDGET + 1))

      expect(described_class.absorb([ long, keyword ])).to eq(1)
      expect(described_class.pluck(:query)).to eq([ keyword[:query] ])
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

  # The reason this table exists beside SearchConsoleRow: Google withholds far
  # more when the page is part of the question, so summing the query x page rows
  # into a keyword series understates it and goes missing on days it should not.
  it "is expected to exceed the sum of the query x page rows for the same query" do
    described_class.absorb([ keyword ])
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: date, query: keyword[:query], page: "https://x/1", clicks: 5, impressions: 150,
        ctr: 0.03, position: 8.0 }
    ])

    expect(sole_item(described_class).clicks).to be > AhoyDashboard::SearchConsoleRow.where(query: keyword[:query]).sum(:clicks)
  end

  it "reads a query's history oldest first" do
    described_class.absorb([
      keyword.merge(date: date, position: 6.0),
      keyword.merge(date: date - 2, position: 9.0),
      keyword.merge(date: date - 1, position: 7.0)
    ])

    expect(described_class.where(query: keyword[:query]).chronological.pluck(:position)).to eq([ 9.0, 7.0, 6.0 ])
  end
end
