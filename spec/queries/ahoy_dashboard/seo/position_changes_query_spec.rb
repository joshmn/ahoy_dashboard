require "rails_helper"

RSpec.describe AhoyDashboard::Seo::PositionChangesQuery do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:range) { (now - 7.days)..now }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:visiting) { create(:dash_serp_keyword, query: "visiting hours") }

  around { |example| travel_to(now) { example.run } }

  def reading(keyword, position:, days_ago:, location: "us", status: :success, url: "https://example.com/a")
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: now - days_ago.days)
    create(:dash_serp_check, run: run, site: site, position: position, url: url, status: status)
  end

  def call(**options)
    described_class.call(site: site, range: range, **options)
  end

  it "compares the first reading in the range against the last, skipping the ones between" do
    reading(visiting, position: 9, days_ago: 6, url: "https://example.com/old")
    reading(visiting, position: 1, days_ago: 4)
    reading(visiting, position: 4, days_ago: 1, url: "https://example.com/new")

    row = sole_item(call.rows)

    expect([ row.query, row.from, row.to, row.change, row.movement, row.url ])
      .to eq([ "visiting hours", 9, 4, 5, :improved, "https://example.com/new" ])
    expect([ row.first_at, row.last_at ]).to eq([ now - 6.days, now - 1.day ])
  end

  it "reads a search with one reading as level and says nothing is comparable" do
    reading(visiting, position: 3, days_ago: 2)

    result = call

    expect(sole_item(result.rows).movement).to eq(:level)
    expect(result).not_to be_comparable
  end

  it "breaks a tie on the reading time by id, the same way both ends" do
    first = reading(visiting, position: 8, days_ago: 3)
    second = reading(visiting, position: 2, days_ago: 3)

    row = sole_item(call.rows)

    expect(first.id).to be < second.id
    expect([ row.from, row.to ]).to eq([ 8, 2 ])
  end

  it "counts arrivals and departures from the edges of the range" do
    mail = create(:dash_serp_keyword, query: "mail rules")
    reading(visiting, position: nil, days_ago: 5)
    reading(visiting, position: 6, days_ago: 1)
    reading(mail, position: 7, days_ago: 5)
    reading(mail, position: nil, days_ago: 1)

    result = call

    expect(result.gained.map(&:query)).to eq([ "visiting hours" ])
    expect(result.lost.map(&:query)).to eq([ "mail rules" ])
  end

  it "leaves out failed readings and readings outside the range" do
    reading(visiting, position: 30, days_ago: 9)
    reading(visiting, position: 5, days_ago: 4)
    reading(visiting, position: 1, days_ago: 2, status: :failed)
    reading(visiting, position: 3, days_ago: 1)

    row = sole_item(call.rows)

    expect([ row.from, row.to ]).to eq([ 5, 3 ])
  end

  it "leaves out a place the keyword no longer searches, the way Rankings does" do
    reading(visiting, position: 5, days_ago: 4)
    reading(visiting, position: 3, days_ago: 1)
    reading(visiting, position: 9, days_ago: 4, location: "gb")
    reading(visiting, position: 2, days_ago: 1, location: "gb")

    expect(call.rows.map(&:location)).to eq(%w[us])
  end

  it "reads nothing without a site" do
    reading(visiting, position: 3, days_ago: 1)

    expect(described_class.call(site: nil, range: range)).not_to be_any
  end
end
