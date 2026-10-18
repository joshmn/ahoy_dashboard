require "rails_helper"

RSpec.describe AhoyDashboard::Serp::CheckNowPresenter do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(AhoyDashboard).to receive(:cache).and_return(cache) }

  def queue(keyword)
    cache.write(AhoyDashboard::Serp::SweepPlanQuery.queued_key(keyword), Time.current.to_i)
  end

  def presenter(**options)
    described_class.new(**options).tap { |shown| allow(shown).to receive(:blocker).and_return(nil) }
  end

  it "says a keyword went out for checking even when the page did not list it up front" do
    keyword = create(:dash_serp_keyword)
    queue(keyword)

    expect(presenter.reason_for(keyword, sites: 1)).to eq("Sent for checking a moment ago.")
  end

  it "reads the listed keywords in one round trip" do
    keywords = create_list(:dash_serp_keyword, 3)
    queue(keywords.second)
    shown = presenter(listed: keywords)
    allow(cache).to receive(:read_multi).and_call_original
    allow(cache).to receive(:exist?).and_call_original

    reasons = keywords.map { |keyword| shown.reason_for(keyword, sites: 1) }

    expect(reasons).to eq([ nil, "Sent for checking a moment ago.", nil ])
    expect(cache).to have_received(:read_multi).once
    expect(cache).not_to have_received(:exist?)
  end
end
