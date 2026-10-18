require "rails_helper"

RSpec.describe AhoyDashboard::Serp::SpendQuery do
  let(:zone) { AhoyDashboard.time_zone }
  let(:now) { zone.local(2026, 9, 20, 10, 0) }

  def day(on, kind: :checks, units: 10, provider: "serpapi")
    create(:dash_serp_spend_day, provider: provider, on: on, kind: kind, units: units)
  end

  def call(provider: :unset, name: nil)
    described_class.call(provider: provider, name: name, now: now)
  end

  it "reports the provider's own counter, because that is what the ceiling reads" do
    record = create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 500, units_spent: 137,
                                                            units_reset_on: Date.new(2026, 9, 1))
    day(Date.new(2026, 9, 3), units: 40)

    result = call(provider: record)

    expect(result).to have_attributes(used: 137, cap: 500, percent: 27, left: 363)
  end

  it "falls back to the ledger when there is no provider row to count against" do
    day(Date.new(2026, 9, 3), units: 40)
    day(Date.new(2026, 9, 4), units: 25)

    result = call(provider: nil, name: "serpapi")

    expect(result).to have_attributes(used: 65, cap: 0, capped?: false, saved?: false, left: nil)
  end

  it "gives one day from the 1st to today, in order" do
    result = call(provider: nil, name: "serpapi")

    expect(result.days.size).to eq(20)
    expect(result.days.first.date).to eq(Date.new(2026, 9, 1))
    expect(result.days.last.date).to eq(Date.new(2026, 9, 20))
  end

  it "splits a day by what the units went on" do
    day(Date.new(2026, 9, 5), kind: :checks, units: 12)
    day(Date.new(2026, 9, 5), kind: :keywords, units: 1)
    day(Date.new(2026, 9, 5), kind: :backlinks, units: 2)

    result = call(provider: nil, name: "serpapi")
    fifth = result.days.find { |entry| entry.date == Date.new(2026, 9, 5) }

    expect(fifth.total).to eq(15)
    expect(fifth.count("keywords")).to eq(1)
    expect(result.count("checks")).to eq(12)
  end

  it "leaves out last month and another provider's spending" do
    day(Date.new(2026, 8, 31), units: 99)
    day(Date.new(2026, 9, 2), units: 99, provider: "dataforseo")
    day(Date.new(2026, 9, 2), units: 7)

    result = call(provider: nil, name: "serpapi")

    expect(result.used).to eq(7)
  end

  it "works out where the month would end up" do
    record = create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 500, units_spent: 400,
                                                            units_reset_on: Date.new(2026, 9, 1))
    allow(AhoyDashboard::Serp::ForecastQuery).to receive(:call).and_return(
      AhoyDashboard::Serp::ForecastQuery::Result.new(checks: 200, backlinks: 10, searches: 200,
                                                     through: now.end_of_month)
    )

    result = call(provider: record)

    expect(result).to have_attributes(projected: 610, over?: true)
    expect(result.near?(80)).to be(true)
  end

  it "is not near a ceiling that does not exist" do
    record = create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 0, units_spent: 9_000,
                                                            units_reset_on: Date.new(2026, 9, 1))

    expect(call(provider: record).near?(80)).to be(false)
  end
end
