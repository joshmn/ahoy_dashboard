require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::Results::StoreCommand do
  let(:run) { create(:dash_serp_run) }

  it "writes a row per result out of the stored pages" do
    create(:dash_serp_run_page, run: run)

    events = described_class.call(run: run)

    expect(events).to have_key(:ok)
    expect(run.results.pluck(:position, :domain)).to eq([ [ 1, "bop.gov" ], [ 2, "example.com" ] ])
    expect(run.results.pluck(:checked_at).uniq).to eq([ run.checked_at ])
  end

  it "replaces what was there rather than doubling it up" do
    create(:dash_serp_run_page, run: run)
    described_class.call(run: run)
    described_class.call(run: run)

    expect(run.results.count).to eq(2)
  end

  it "says so when there is no readable page to read" do
    events = described_class.call(run: run)

    expect(events).to have_key(:nothing)
    expect(run.results).to be_empty
  end
end
