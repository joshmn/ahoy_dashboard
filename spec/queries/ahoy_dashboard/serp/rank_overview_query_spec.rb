require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::RankOverviewQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:range) { (now - 30.days)..now }
  let(:site) { create(:dash_serp_site, domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  def reading(keyword:, at:, position:, location: "us", overview: nil, cited: nil)
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    create(:dash_serp_check, run: run, keyword: keyword, site: site, target: target,
           location: location, checked_at: at, position: position,
           ai_overview_present: overview, ai_overview_cited: cited)
  end

  it "reads the latest reading as the current one and the one before it as the comparison" do
    keyword = create(:dash_serp_keyword)
    reading(keyword: keyword, at: now - 2.days, position: 9)
    reading(keyword: keyword, at: now - 1.day, position: 4)

    row = sole_item(described_class.call(site: site, range: range).rows)

    expect(row.position).to eq(4)
    expect(row.previous.position).to eq(9)
    expect(row.change).to eq(5)
    expect(row.best).to eq(4)
    expect(row.worst).to eq(9)
  end

  it "counts a fall in the number as an improvement, because position runs backwards" do
    keyword = create(:dash_serp_keyword)
    reading(keyword: keyword, at: now - 2.days, position: 4)
    reading(keyword: keyword, at: now - 1.day, position: 9)

    expect(sole_item(described_class.call(site: site, range: range).rows).change).to eq(-5)
  end

  it "keeps each place its own row" do
    keyword = create(:dash_serp_keyword, locations: %w[us gb])
    reading(keyword: keyword, at: now - 1.day, position: 3, location: "us")
    reading(keyword: keyword, at: now - 1.day, position: 20, location: "gb")

    rows = described_class.call(site: site, range: range).rows

    expect(rows.map { |row| [ row.location, row.position ] }).to eq([ [ "us", 3 ], [ "gb", 20 ] ])
  end

  it "puts the ones ranking first and the ones nowhere at the end" do
    good = create(:dash_serp_keyword, query: "zzz good")
    gone = create(:dash_serp_keyword, query: "aaa gone")
    reading(keyword: good, at: now - 1.day, position: 2)
    reading(keyword: gone, at: now - 1.day, position: nil)

    rows = described_class.call(site: site, range: range).rows

    expect(rows.map { |row| row.keyword.query }).to eq([ "zzz good", "aaa gone" ])
    expect(rows.last).not_to be_ranked
  end

  it "counts the tops and the median off the ones that rank" do
    %w[a b c d].each_with_index do |name, index|
      keyword = create(:dash_serp_keyword, query: name)
      reading(keyword: keyword, at: now - 1.day, position: [ 1, 2, 12, nil ][index])
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
    reading(keyword: shown, at: now - 1.day, position: 4, overview: true, cited: false)
    reading(keyword: quoted, at: now - 1.day, position: 4, overview: true, cited: true)

    result = described_class.call(site: site, range: range)

    expect(result.overviews).to eq(2)
    expect(result.cited).to eq(1)
  end

  it "leaves out readings outside the range" do
    keyword = create(:dash_serp_keyword)
    reading(keyword: keyword, at: now - 90.days, position: 1)

    expect(described_class.call(site: site, range: range).rows).to be_empty
  end

  it "answers with nothing rather than raising when no site is set up" do
    expect(described_class.call(site: nil, range: range).rows).to be_empty
  end

  it "keeps historical extremes and totals while loading only the latest two checks" do
    keyword = create(:dash_serp_keyword)
    reading(keyword: keyword, at: now - 4.days, position: 1)
    reading(keyword: keyword, at: now - 3.days, position: 50)
    previous = reading(keyword: keyword, at: now - 1.day, position: 9)
    current = reading(keyword: keyword, at: now - 1.day, position: nil)
    loaded = []
    subscriber = ->(_name, _started, _finished, _id, payload) { loaded << payload[:record_count] if payload[:class_name] == "AhoyDashboard::SerpCheck" }

    result = ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      described_class.call(site: site, range: range)
    end

    expect(sole_item(result.rows)).to have_attributes(current: current, previous: previous, best: 1, worst: 50, count: 4)
    expect(loaded.sum).to eq(2)
    expect(sole_item(result.rows).current.association(:run)).to be_loaded
    expect(sole_item(result.rows).current.run.requested_pages).to eq(current.run.requested_pages)
  end

  it "preserves first-reading order when displayed ranking keys tie" do
    first = create(:dash_serp_keyword, query: "same words", device: "desktop")
    second = create(:dash_serp_keyword, query: "same words", device: "mobile")
    reading(keyword: second, at: now - 4.days, position: 5)
    reading(keyword: first, at: now - 3.days, position: 5)
    reading(keyword: first, at: now - 2.days, position: 5)
    reading(keyword: second, at: now - 1.day, position: 5)

    expect(described_class.call(site: site, range: range).rows.map(&:keyword)).to eq([ second, first ])
  end
end
