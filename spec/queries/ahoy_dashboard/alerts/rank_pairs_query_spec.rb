require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::RankPairsQuery do
  let(:site) { create(:dash_serp_site) }
  let(:keyword) { create(:dash_serp_keyword, locations: [ "us" ]) }
  let(:since) { 2.days.ago.change(usec: 0) }

  def reading(location:, at:, site: self.site, status: :success)
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    create(:dash_serp_check, run: run, site: site, status: status)
  end

  it "loads only active locations while retaining older predecessors and ignoring failed or other-site checks" do
    previous = reading(location: "us", at: since - 3.days)
    current = reading(location: "us", at: since)
    reading(location: "gb", at: since - 3.days)
    reading(location: "gb", at: since - 1.day)
    reading(location: "gb", at: since + 1.hour, status: :failed)
    reading(location: "gb", at: since + 2.hours, site: create(:dash_serp_site))
    loaded = 0
    subscriber = ->(_name, _started, _finished, _id, payload) do
      loaded += payload[:record_count] if payload[:class_name] == "AhoyDashboard::SerpCheck"
    end

    pairs = ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      described_class.call(site: site, since: since)
    end

    expect(sole_item(pairs)).to have_attributes(keyword: keyword, location: "us", now: current, before: previous)
    expect(loaded).to eq(2)
  end

  it "preserves timestamp tie-breaking and includes active locations removed from keyword settings" do
    previous = reading(location: "ca", at: since)
    current = reading(location: "ca", at: since)
    latest = reading(location: "us", at: since + 1.hour)

    pairs = described_class.call(site: site, since: since)

    expect(pairs.map(&:location)).to eq(%w[ca us])
    expect(pairs.first).to have_attributes(now: current, before: previous)
    expect(pairs.last).to have_attributes(now: latest, before: nil)
  end

  it "returns no pairs without a site" do
    expect(described_class.call(site: nil, since: since)).to be_empty
  end
end
