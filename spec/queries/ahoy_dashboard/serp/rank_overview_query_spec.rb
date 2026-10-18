require "rails_helper"

RSpec.describe AhoyDashboard::Serp::RankOverviewQuery do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:range) { (now - 30.days)..now }
  let(:site) { create(:dash_serp_site, domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  it "reads the latest reading as the current one and the one before it as the comparison" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, site: site, at: now - 2.days, position: 9)
    serp_reading(keyword, site: site, at: now - 1.day, position: 4)

    row = sole_item(described_class.call(site: site, range: range).rows)

    expect(row.position).to eq(4)
    expect(row.previous.position).to eq(9)
    expect(row.change).to eq(5)
    expect(row.best).to eq(4)
    expect(row.worst).to eq(9)
  end

  it "counts a fall in the number as an improvement, because position runs backwards" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, site: site, at: now - 2.days, position: 4)
    serp_reading(keyword, site: site, at: now - 1.day, position: 9)

    expect(sole_item(described_class.call(site: site, range: range).rows).change).to eq(-5)
  end

  it "keeps each place its own row" do
    keyword = create(:dash_serp_keyword, locations: %w[us gb])
    serp_reading(keyword, site: site, at: now - 1.day, position: 3, location: "us")
    serp_reading(keyword, site: site, at: now - 1.day, position: 20, location: "gb")

    rows = described_class.call(site: site, range: range).rows

    expect(rows.map { |row| [ row.location, row.position ] }).to eq([ [ "us", 3 ], [ "gb", 20 ] ])
  end

  it "puts the ones ranking first and the ones nowhere at the end" do
    good = create(:dash_serp_keyword, query: "zzz good")
    gone = create(:dash_serp_keyword, query: "aaa gone")
    serp_reading(good, site: site, at: now - 1.day, position: 2)
    serp_reading(gone, site: site, at: now - 1.day, position: nil)

    rows = described_class.call(site: site, range: range).rows

    expect(rows.map { |row| row.keyword.query }).to eq([ "zzz good", "aaa gone" ])
    expect(rows.last).not_to be_ranked
  end

  it "counts the tops and the median off the ones that rank" do
    %w[a b c d].each_with_index do |name, index|
      keyword = create(:dash_serp_keyword, query: name)
      serp_reading(keyword, site: site, at: now - 1.day, position: [ 1, 2, 12, nil ][index])
    end

    result = described_class.call(site: site, range: range)

    expect(result.tracked).to eq(4)
    expect(result.ranked).to eq(3)
    expect(result.top_three).to eq(2)
    expect(result.top_ten).to eq(2)
    expect(result.median).to eq(2)
  end

  it "counts overviews and the ones that cited us" do
    shown = create(:dash_serp_keyword, query: "shown")
    quoted = create(:dash_serp_keyword, query: "quoted")
    serp_reading(shown, site: site, at: now - 1.day, position: 4, ai_overview_present: true, ai_overview_cited: false)
    serp_reading(quoted, site: site, at: now - 1.day, position: 4, ai_overview_present: true, ai_overview_cited: true)

    result = described_class.call(site: site, range: range)

    expect(result.overviews).to eq(2)
    expect(result.cited).to eq(1)
  end

  it "leaves out readings outside the range" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, site: site, at: now - 90.days, position: 1)

    expect(described_class.call(site: site, range: range).rows).to be_empty
  end

  it "answers with nothing rather than raising when no site is set up" do
    expect(described_class.call(site: nil, range: range).rows).to be_empty
  end

  it "keeps historical extremes and totals while loading only the latest two checks" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, site: site, at: now - 4.days, position: 1)
    serp_reading(keyword, site: site, at: now - 3.days, position: 50)
    previous = serp_reading(keyword, site: site, at: now - 1.day, position: 9)
    current = serp_reading(keyword, site: site, at: now - 1.day, position: nil)
    result = nil
    loaded = instantiated(AhoyDashboard::SerpCheck) { result = described_class.call(site: site, range: range) }

    expect(sole_item(result.rows)).to have_attributes(current: current, previous: previous, best: 1, worst: 50, count: 4)
    expect(loaded).to eq(2)
    expect(sole_item(result.rows).current.association(:run)).to be_loaded
    expect(sole_item(result.rows).current.run.requested_pages).to eq(current.run.requested_pages)
  end

  it "preserves first-reading order when displayed ranking keys tie" do
    first = create(:dash_serp_keyword, query: "same words", device: "desktop")
    second = create(:dash_serp_keyword, query: "same words", device: "mobile")
    serp_reading(second, site: site, at: now - 4.days, position: 5)
    serp_reading(first, site: site, at: now - 3.days, position: 5)
    serp_reading(first, site: site, at: now - 2.days, position: 5)
    serp_reading(second, site: site, at: now - 1.day, position: 5)

    expect(described_class.call(site: site, range: range).rows.map(&:keyword)).to eq([ second, first ])
  end
end
