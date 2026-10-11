require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Spend do
  let(:today) { Time.current.in_time_zone(AhoyDashboard.time_zone).to_date }

  def ledger
    AhoyDashboard::SerpSpendDay.order(:on, :kind).pluck(:provider, :on, :kind, :units)
  end

  it "writes the day what was actually spent, not what was reserved" do
    record = create(:dash_serp_provider, :serpapi, monthly_cap_units: 500)
    spend = described_class.new(provider: record, units: 5, kind: :checks)

    spend.reserve
    spend.settle(3)

    expect(ledger).to eq([ [ "serpapi", today, "checks", 3 ] ])
    expect(record.reload.units_spent).to eq(3)
  end

  it "writes the day once however often settle is called" do
    record = create(:dash_serp_provider, :serpapi, monthly_cap_units: 500)
    spend = described_class.new(provider: record, units: 2, kind: :checks)

    spend.reserve
    3.times { spend.settle(2) }

    expect(ledger).to eq([ [ "serpapi", today, "checks", 2 ] ])
  end

  it "adds to the day a later spend of the same kind lands on" do
    record = create(:dash_serp_provider, :serpapi, monthly_cap_units: 500)

    2.times do
      spend = described_class.new(provider: record, units: 4, kind: :checks)
      spend.reserve
      spend.settle(4)
    end

    expect(ledger).to eq([ [ "serpapi", today, "checks", 8 ] ])
  end

  it "keeps each kind of spending apart" do
    record = create(:dash_serp_provider, :serpapi, monthly_cap_units: 500)

    { checks: 6, keywords: 1, backlinks: 2 }.each do |kind, units|
      spend = described_class.new(provider: record, units: units, kind: kind)
      spend.reserve
      spend.settle(units)
    end

    expect(ledger).to contain_exactly([ "serpapi", today, "checks", 6 ], [ "serpapi", today, "keywords", 1 ],
                                      [ "serpapi", today, "backlinks", 2 ])
  end

  it "records a day for credentials in the initializer, which have no provider row at all" do
    spend = described_class.new(provider: nil, units: 3, kind: :checks, name: "serpapi")

    spend.reserve
    spend.settle(3)

    expect(ledger).to eq([ [ "serpapi", today, "checks", 3 ] ])
  end

  it "writes nothing when a check comes back with nothing spent" do
    record = create(:dash_serp_provider, :serpapi, monthly_cap_units: 500)
    spend = described_class.new(provider: record, units: 2, kind: :checks)

    spend.reserve
    spend.settle(0)

    expect(ledger).to be_empty
    expect(record.reload.units_spent).to eq(0)
  end

  it "writes nothing when the cap refused the reservation" do
    record = create(:dash_serp_provider, :serpapi, :spent, monthly_cap_units: 500)
    spend = described_class.new(provider: record, units: 5, kind: :checks)

    expect(spend.reserve).to be(false)
    spend.settle(0)

    expect(ledger).to be_empty
  end

  it "keeps spending when the ledger table is missing" do
    record = create(:dash_serp_provider, :serpapi, monthly_cap_units: 500)
    allow(AhoyDashboard::SerpSpendDay).to receive(:upsert_all).and_raise(ActiveRecord::StatementInvalid, "no table")
    spend = described_class.new(provider: record, units: 4, kind: :checks)

    spend.reserve
    expect { spend.settle(4) }.not_to raise_error

    expect(record.reload.units_spent).to eq(4)
  end
end
