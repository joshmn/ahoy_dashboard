require "rails_helper"

RSpec.describe AhoyDashboard::Serp::KeywordSeriesQuery do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:range) { (now - 30.days)..now }
  let(:site) { create(:dash_serp_site, domain: "example.com") }
  let(:keyword) { create(:dash_serp_keyword, locations: %w[us gb]) }

  around { |example| travel_to(now) { example.run } }

  it "reads one place at a time and opens on the first" do
    serp_reading(keyword, site: site, at: now - 1.day, position: 3, location: "us")
    serp_reading(keyword, site: site, at: now - 1.day, position: 30, location: "gb")

    result = described_class.call(keyword: keyword, site: site, range: range)

    expect(result.location).to eq("us")
    expect(result.points.map(&:position)).to eq([ 3 ])
    expect(result.locations).to eq(%w[us gb])
  end

  it "reads the place that was asked for" do
    serp_reading(keyword, site: site, at: now - 1.day, position: 30, location: "gb")

    result = described_class.call(keyword: keyword, site: site, range: range, location: "gb")

    expect(result.position).to eq(30)
  end

  it "falls back to the first place when asked for one it is not checked from" do
    serp_reading(keyword, site: site, at: now - 1.day, position: 3)

    result = described_class.call(keyword: keyword, site: site, range: range, location: "fr")

    expect(result.location).to eq("us")
  end

  it "runs oldest first, so a chart reads left to right" do
    serp_reading(keyword, site: site, at: now - 3.days, position: 8)
    serp_reading(keyword, site: site, at: now - 1.day, position: 5)

    expect(described_class.call(keyword: keyword, site: site, range: range).points.map(&:position))
      .to eq([ 8, 5 ])
  end

  it "keeps a reading where the site was nowhere, without calling it a position" do
    serp_reading(keyword, site: site, at: now - 2.days, position: 6)
    serp_reading(keyword, site: site, at: now - 1.day, position: nil)

    result = described_class.call(keyword: keyword, site: site, range: range)

    expect(result.points.size).to eq(2)
    expect(result.ranked.size).to eq(1)
    expect(result.position).to be_nil
    expect(result.best).to eq(6)
  end

  it "counts the overviews and the ones that quoted us" do
    serp_reading(keyword, site: site, at: now - 2.days, position: 6, ai_overview_present: true, ai_overview_cited: false)
    serp_reading(keyword, site: site, at: now - 1.day, position: 6, ai_overview_present: true, ai_overview_cited: true)

    result = described_class.call(keyword: keyword, site: site, range: range)

    expect(result.overviews).to eq(2)
    expect(result.citations).to eq(1)
  end

  it "answers with nothing rather than raising when no site is set up" do
    expect(described_class.call(keyword: keyword, site: nil, range: range).points).to be_empty
  end

  it "only loads the run whose results are shown while preserving every chart reading" do
    5.times { |day| serp_reading(keyword, site: site, at: now - day.days, position: day + 1) }
    result = nil
    loaded = instantiated(AhoyDashboard::SerpRun) { result = described_class.call(keyword: keyword, site: site, range: range) }

    expect(result.points.map(&:position)).to eq([ 5, 4, 3, 2, 1 ])
    expect(result.run).to eq(result.current.run)
    expect(loaded).to eq(1)
  end
end
