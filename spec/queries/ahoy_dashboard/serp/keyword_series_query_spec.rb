require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::KeywordSeriesQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:range) { (now - 30.days)..now }
  let(:site) { create(:dash_serp_site, domain: "example.com") }
  let(:keyword) { create(:dash_serp_keyword, locations: %w[us gb]) }

  around { |example| travel_to(now) { example.run } }

  def reading(at:, position:, location: "us", overview: nil, cited: nil)
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    create(:dash_serp_check, run: run, keyword: keyword, site: site, target: target,
           location: location, checked_at: at, position: position,
           ai_overview_present: overview, ai_overview_cited: cited)
  end

  it "reads one place at a time and opens on the first" do
    reading(at: now - 1.day, position: 3, location: "us")
    reading(at: now - 1.day, position: 30, location: "gb")

    result = described_class.call(keyword: keyword, site: site, range: range)

    expect(result.location).to eq("us")
    expect(result.points.map(&:position)).to eq([ 3 ])
    expect(result.locations).to eq(%w[us gb])
  end

  it "reads the place that was asked for" do
    reading(at: now - 1.day, position: 30, location: "gb")

    result = described_class.call(keyword: keyword, site: site, range: range, location: "gb")

    expect(result.position).to eq(30)
  end

  it "falls back to the first place when asked for one it is not checked from" do
    reading(at: now - 1.day, position: 3)

    result = described_class.call(keyword: keyword, site: site, range: range, location: "fr")

    expect(result.location).to eq("us")
  end

  it "runs oldest first, so a chart reads left to right" do
    reading(at: now - 3.days, position: 8)
    reading(at: now - 1.day, position: 5)

    expect(described_class.call(keyword: keyword, site: site, range: range).points.map(&:position))
      .to eq([ 8, 5 ])
  end

  it "keeps a reading where the site was nowhere, without calling it a position" do
    reading(at: now - 2.days, position: 6)
    reading(at: now - 1.day, position: nil)

    result = described_class.call(keyword: keyword, site: site, range: range)

    expect(result.points.size).to eq(2)
    expect(result.ranked.size).to eq(1)
    expect(result.position).to be_nil
    expect(result.best).to eq(6)
  end

  it "counts the overviews and the ones that quoted us" do
    reading(at: now - 2.days, position: 6, overview: true, cited: false)
    reading(at: now - 1.day, position: 6, overview: true, cited: true)

    result = described_class.call(keyword: keyword, site: site, range: range)

    expect(result.overviews).to eq(2)
    expect(result.citations).to eq(1)
  end

  it "answers with nothing rather than raising when no site is set up" do
    expect(described_class.call(keyword: keyword, site: nil, range: range).points).to be_empty
  end

  it "only loads the run whose results are shown while preserving every chart reading" do
    5.times { |day| reading(at: now - day.days, position: day + 1) }
    loaded = []
    subscriber = ->(_name, _started, _finished, _id, payload) { loaded << payload[:record_count] if payload[:class_name] == "AhoyDashboard::SerpRun" }

    result = ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      described_class.call(keyword: keyword, site: site, range: range)
    end

    expect(result.points.map(&:position)).to eq([ 5, 4, 3, 2, 1 ])
    expect(result.run).to eq(result.current.run)
    expect(loaded.sum).to eq(1)
  end
end
