require "rails_helper"

RSpec.describe AhoyDashboard::Serp::ForecastQuery do
  let(:zone) { AhoyDashboard.time_zone }
  let(:now) { zone.local(2026, 9, 20, 10, 0) }

  before { allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true) }

  def keyword(frequency: :daily, last: nil, locations: [ "us" ], pages: 1, enabled: true)
    create(:dash_serp_keyword, :tracked, frequency: frequency, last_checked_at: last, locations: locations,
                                         pages: pages, enabled: enabled)
  end

  def call(name: :serpapi)
    described_class.call(name: name, now: now)
  end

  it "counts every check a daily keyword has left in the month" do
    keyword(last: now)

    expect(call.checks).to eq(10)
  end

  it "counts a keyword that is already due from now" do
    keyword(last: now - 3.days)

    expect(call.checks).to eq(11)
  end

  it "counts a keyword that has never been checked from now" do
    keyword(last: nil)

    expect(call.checks).to eq(11)
  end

  it "counts a weekly keyword once a week" do
    keyword(frequency: :weekly, last: now)

    expect(call.checks).to eq(1)
  end

  it "counts nothing for a monthly keyword whose next check is next month" do
    keyword(frequency: :monthly, last: now)

    expect(call.checks).to eq(0)
  end

  it "charges every place and every page of a check" do
    keyword(last: now, locations: %w[us gb], pages: 2)

    expect(call.checks).to eq(10 * 2 * 2)
  end

  it "leaves out a paused keyword" do
    keyword(last: now, enabled: false)

    expect(call.checks).to eq(0)
  end

  it "leaves out a keyword with no site on it" do
    create(:dash_serp_keyword, frequency: :daily, last_checked_at: now)

    expect(call.checks).to eq(0)
  end

  it "counts nothing at all while rank tracking is off" do
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
    keyword(last: now)

    expect(call.checks).to eq(0)
  end

  it "counts the searches behind the units" do
    keyword(last: now, locations: %w[us gb])

    expect(call.searches).to eq(20)
  end

  it "leaves backlinks out when they run through another provider" do
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::Backlinks).to receive(:provider).and_return(:dataforseo)

    expect(call.backlinks).to eq(0)
  end

  it "counts the daily backlink syncs that spend from the same ceiling" do
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::Backlinks).to receive(:provider).and_return(:serpapi)
    allow(AhoyDashboard::Backlinks).to receive(:available?).and_return(true)
    AhoyDashboard::JobRun.create!(key: "backlinks", last_run_at: now)

    expect(call.backlinks).to eq(10 * AhoyDashboard::Backlinks.adapter_class.backlink_cost_units)
  end
end
