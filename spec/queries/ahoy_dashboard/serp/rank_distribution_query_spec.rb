require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::RankDistributionQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:range) { (now - 6.days).beginning_of_day..now.end_of_day }
  let(:site) { create(:dash_serp_site, domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  def reading(keyword:, at:, position:, location: "us", status: :success, on: site)
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: on)
    create(:dash_serp_check, run: run, keyword: keyword, site: on, target: target,
           location: location, checked_at: at, position: position, status: status)
  end

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
    reads = []
    subscriber = ->(_name, _started, _finished, _id, payload) { reads << payload[:sql] if payload[:sql].include?('FROM "ahoy_dashboard_settings"') }

    result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.call(site: selected_site, range: selected_range, now: now)
    end

    expect(result.days.size).to eq(7)
    expect(reads.size).to eq(1)
  end

  it "puts each position in its band" do
    [ 1, 3, 4, 10, 11, 20, 21, 48, nil ].each_with_index do |position, index|
      reading(keyword: create(:dash_serp_keyword, query: "q#{index}"), at: now - 1.hour, position: position)
    end

    latest = call.latest

    expect(latest.counts).to eq("top-3" => 2, "4-10" => 2, "11-20" => 2, "past-20" => 2, "not-found" => 1)
  end

  it "carries a reading forward to the days after it, so a weekly keyword does not come and go" do
    keyword = create(:dash_serp_keyword, frequency: :weekly)
    reading(keyword: keyword, at: now - 5.days, position: 2)

    result = call

    expect(day(result, Date.new(2026, 8, 14)).total).to eq(0)
    expect(result.days.drop(1).map { |candidate| candidate.count("top-3") }).to all(eq(1))
  end

  it "counts a series on the days before its first check in the range off its last check before the range" do
    keyword = create(:dash_serp_keyword)
    reading(keyword: keyword, at: now - 20.days, position: 15)
    reading(keyword: keyword, at: now - 2.days, position: 5)

    result = call

    expect(day(result, Date.new(2026, 8, 14)).count("11-20")).to eq(1)
    expect(day(result, Date.new(2026, 8, 18)).counts.values_at("11-20", "4-10")).to eq([ 0, 1 ])
  end

  it "leaves out a series with nothing in the range, like the keyword list does" do
    reading(keyword: create(:dash_serp_keyword), at: now - 20.days, position: 1)

    expect(call).not_to be_any
  end

  it "uses the latest reading of a day when a search was checked twice that day" do
    keyword = create(:dash_serp_keyword)
    reading(keyword: keyword, at: now - 3.hours, position: 30)
    reading(keyword: keyword, at: now - 1.hour, position: 2)

    expect(call.latest.counts.values_at("top-3", "past-20")).to eq([ 1, 0 ])
  end

  it "counts each place on its own" do
    keyword = create(:dash_serp_keyword, locations: %w[us gb])
    reading(keyword: keyword, at: now - 1.hour, position: 2, location: "us")
    reading(keyword: keyword, at: now - 1.hour, position: nil, location: "gb")

    expect(call.latest.counts.values_at("top-3", "not-found")).to eq([ 1, 1 ])
  end

  it "ignores failed checks and other sites" do
    keyword = create(:dash_serp_keyword)
    rival = create(:dash_serp_site, domain: "rival.com")
    reading(keyword: keyword, at: now - 1.hour, position: nil, status: :failed)
    reading(keyword: keyword, at: now - 1.hour, position: 1, on: rival)

    expect(call).not_to be_any
  end

  it "matches the bands of the keyword list's latest readings on the last day" do
    keyword = create(:dash_serp_keyword)
    reading(keyword: keyword, at: now - 4.days, position: 3)
    reading(keyword: keyword, at: now - 1.day, position: 14)

    row = sole_item(AhoyDashboard::Serp::RankOverviewQuery.call(site: site, range: range).rows)
    band = AhoyDashboard::Serp::RankBand.for(row.position)

    expect(call.latest.count(band.key)).to eq(1)
    expect(call.latest.total).to eq(1)
  end

  it "counts only keywords carrying the tag when one is picked" do
    reading(keyword: create(:dash_serp_keyword, query: "visiting", tags: %w[visits]), at: now - 1.hour, position: 2)
    reading(keyword: create(:dash_serp_keyword, query: "mail"), at: now - 1.hour, position: 15)

    latest = described_class.call(site: site, range: range, tag: "visits").latest

    expect(latest.counts.values_at("top-3", "11-20")).to eq([ 1, 0 ])
  end

  it "is empty with no site" do
    expect(described_class.call(site: nil, range: range).days).to be_empty
  end

  it "carries sparse and tied readings forward exactly through a partial final day" do
    range = (now - 30.days).beginning_of_day..now
    random = Random.new(42)
    series = 8.times.map do |key|
      readings = Array.new(20) do
        at = range.begin + random.rand(-2..31).days + random.rand(0..23).hours
        described_class::Reading.new(at: at, position: [ nil, 1, 4, 11, 21 ][random.rand(5)])
      end.sort_by(&:at)
      [ key, readings ]
    end.to_h
    query = described_class.new(site: site, range: range, now: now)
    allow(query).to receive(:readings).and_return(series)

    expected = (range.begin.to_date..now.to_date).map do |date|
      cutoff = [ date.in_time_zone(AhoyDashboard.time_zone).end_of_day, now ].min
      counts = AhoyDashboard::Serp::RankBand::KEYS.index_with(0)
      series.each_value do |readings|
        latest = readings.select { |reading| reading.at <= cutoff }.last
        counts[AhoyDashboard::Serp::RankBand.for(latest.position).key] += 1 if latest
      end
      [ date, counts ]
    end

    expect(query.call.days.map { |day| [ day.date, day.counts ] }).to eq(expected)
  end
end
