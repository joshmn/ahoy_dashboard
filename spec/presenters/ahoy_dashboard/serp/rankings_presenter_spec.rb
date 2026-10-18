require "rails_helper"

RSpec.describe AhoyDashboard::Serp::RankingsPresenter do
  it "reuses a single-place decision without repeatedly parsing all rows" do
    row = double(place: double(label: "US"))
    presenter = described_class.new(query: nil, result: double(rows: [ row ]), visibility: nil,
                                    share: nil, site: nil, sites: [])
    expect(row).to receive(:place).once.and_return(double(label: "US"))

    20.times { expect(presenter.places?).to be(false) }
  end

  it "reads the dashboard time zone once for all daily chart labels" do
    presenter = described_class.new(query: nil, result: nil, visibility: nil, share: nil, site: nil, sites: [])
    AhoyDashboard::Setting.write(AhoyDashboard::Setting::TIME_ZONE, "America/Los_Angeles")
    day = AhoyDashboard::Serp::RankDistributionQuery::Day.new(date: Date.new(2026, 8, 10), counts: {})
    reads = setting_reads { 20.times { expect(presenter.day_title(day)).to start_with("Aug 10") } }

    expect(reads).to eq(1)
  end
end
