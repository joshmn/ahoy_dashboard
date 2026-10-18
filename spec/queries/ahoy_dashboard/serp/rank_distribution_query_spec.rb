require "rails_helper"

RSpec.describe AhoyDashboard::Serp::RankDistributionQuery do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:range) { (now - 6.days).beginning_of_day..now.end_of_day }
  let(:site) { create(:dash_serp_site, domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  def call
    described_class.call(site: site, range: range)
  end

  def day(result, date)
    result.days.find { |candidate| candidate.date == date }
  end

  it "draws one day per date in the range and stops at today" do
    result = described_class.call(site: site, range: (now - 2.days).beginning_of_day..(now + 5.days))

    expect(result.days.map(&:date)).to eq([ Date.new(2026, 8, 18), Date.new(2026, 8, 19), Date.new(2026, 8, 20) ])
  end

  it "reads the time-zone setting once rather than once per daily cutoff" do
    selected_site, selected_range = site, range
    result = nil
    reads = setting_reads { result = described_class.call(site: selected_site, range: selected_range, now: now) }

    expect(result.days.size).to eq(7)
    expect(reads).to eq(1)
  end

  it "puts each position in its band" do
    [ 1, 3, 4, 10, 11, 20, 21, 48, nil ].each_with_index do |position, index|
      serp_reading(create(:dash_serp_keyword, query: "q#{index}"), site: site, at: now - 1.hour, position: position)
    end

    latest = call.latest

    expect(latest.counts).to eq("top-3" => 2, "4-10" => 2, "11-20" => 2, "past-20" => 2, "not-found" => 1)
  end

  it "carries a reading forward to the days after it, so a weekly keyword does not come and go" do
    keyword = create(:dash_serp_keyword, frequency: :weekly)
    serp_reading(keyword, site: site, at: now - 5.days, position: 2)

    result = call

    expect(day(result, Date.new(2026, 8, 14)).total).to eq(0)
    expect(result.days.drop(1).map { |candidate| candidate.count("top-3") }).to all(eq(1))
  end

  it "counts a series on the days before its first check in the range off its last check before the range" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, site: site, at: now - 20.days, position: 15)
    serp_reading(keyword, site: site, at: now - 2.days, position: 5)

    result = call

    expect(day(result, Date.new(2026, 8, 14)).count("11-20")).to eq(1)
    expect(day(result, Date.new(2026, 8, 18)).counts.values_at("11-20", "4-10")).to eq([ 0, 1 ])
  end

  it "leaves out a series with nothing in the range, like the keyword list does" do
    serp_reading(create(:dash_serp_keyword), site: site, at: now - 20.days, position: 1)

    expect(call).not_to be_any
  end

  it "uses the latest reading of a day when a search was checked twice that day" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, site: site, at: now - 3.hours, position: 30)
    serp_reading(keyword, site: site, at: now - 1.hour, position: 2)

    expect(call.latest.counts.values_at("top-3", "past-20")).to eq([ 1, 0 ])
  end

  it "counts each place on its own" do
    keyword = create(:dash_serp_keyword, locations: %w[us gb])
    serp_reading(keyword, site: site, at: now - 1.hour, position: 2, location: "us")
    serp_reading(keyword, site: site, at: now - 1.hour, position: nil, location: "gb")

    expect(call.latest.counts.values_at("top-3", "not-found")).to eq([ 1, 1 ])
  end

  it "ignores failed checks and other sites" do
    keyword = create(:dash_serp_keyword)
    rival = create(:dash_serp_site, domain: "rival.com")
    serp_reading(keyword, site: site, at: now - 1.hour, position: nil, status: :failed)
    serp_reading(keyword, site: rival, at: now - 1.hour, position: 1)

    expect(call).not_to be_any
  end

  it "matches the bands of the keyword list's latest readings on the last day" do
    keyword = create(:dash_serp_keyword)
    serp_reading(keyword, site: site, at: now - 4.days, position: 3)
    serp_reading(keyword, site: site, at: now - 1.day, position: 14)

    row = sole_item(AhoyDashboard::Serp::RankOverviewQuery.call(site: site, range: range).rows)
    band = AhoyDashboard::Serp::RankBand.for(row.position)

    expect(call.latest.count(band.key)).to eq(1)
    expect(call.latest.total).to eq(1)
  end

  it "counts only keywords carrying the tag when one is picked" do
    serp_reading(create(:dash_serp_keyword, query: "visiting", tags: %w[visits]), site: site, at: now - 1.hour, position: 2)
    serp_reading(create(:dash_serp_keyword, query: "mail"), site: site, at: now - 1.hour, position: 15)

    latest = described_class.call(site: site, range: range, tag: "visits").latest

    expect(latest.counts.values_at("top-3", "11-20")).to eq([ 1, 0 ])
  end

  it "is empty with no site" do
    expect(described_class.call(site: nil, range: range).days).to be_empty
  end

  it "carries sparse and tied readings forward exactly through a partial final day" do
    range = (now - 6.days).beginning_of_day..now
    seeded = create(:dash_serp_keyword, query: "seeded")
    tied = create(:dash_serp_keyword, query: "tied")
    late = create(:dash_serp_keyword, query: "late")
    serp_reading(seeded, site: site, at: dash_time(2026, 8, 10, 12), position: 15)
    serp_reading(seeded, site: site, at: dash_time(2026, 8, 16, 8), position: 2)
    serp_reading(seeded, site: site, at: dash_time(2026, 8, 18, 10), position: nil)
    serp_reading(tied, site: site, at: dash_time(2026, 8, 15, 6), position: 25)
    serp_reading(tied, site: site, at: dash_time(2026, 8, 15, 6), position: 5)
    serp_reading(tied, site: site, at: dash_time(2026, 8, 19, 23), position: 11)
    serp_reading(late, site: site, at: dash_time(2026, 8, 17, 3), position: 30)
    serp_reading(late, site: site, at: dash_time(2026, 8, 17, 20), position: 7)
    serp_reading(late, site: site, at: dash_time(2026, 8, 20, 8), position: 1)
    serp_reading(late, site: site, at: dash_time(2026, 8, 20, 10), position: 50)
    serp_reading(create(:dash_serp_keyword, query: "gone"), site: site, at: dash_time(2026, 8, 12, 9), position: 3)

    days = described_class.call(site: site, range: range).days

    expect(days.map { |day| [ day.date, day.counts ] }).to eq([
      [ Date.new(2026, 8, 14), { "top-3" => 0, "4-10" => 0, "11-20" => 1, "past-20" => 0, "not-found" => 0 } ],
      [ Date.new(2026, 8, 15), { "top-3" => 0, "4-10" => 1, "11-20" => 1, "past-20" => 0, "not-found" => 0 } ],
      [ Date.new(2026, 8, 16), { "top-3" => 1, "4-10" => 1, "11-20" => 0, "past-20" => 0, "not-found" => 0 } ],
      [ Date.new(2026, 8, 17), { "top-3" => 1, "4-10" => 2, "11-20" => 0, "past-20" => 0, "not-found" => 0 } ],
      [ Date.new(2026, 8, 18), { "top-3" => 0, "4-10" => 2, "11-20" => 0, "past-20" => 0, "not-found" => 1 } ],
      [ Date.new(2026, 8, 19), { "top-3" => 0, "4-10" => 1, "11-20" => 1, "past-20" => 0, "not-found" => 1 } ],
      [ Date.new(2026, 8, 20), { "top-3" => 1, "4-10" => 0, "11-20" => 1, "past-20" => 0, "not-found" => 1 } ]
    ])
  end
end
