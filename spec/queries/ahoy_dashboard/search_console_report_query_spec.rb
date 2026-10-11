require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleReportQuery do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:day) { Date.new(2026, 8, 12) }
  let(:range) { (now - 30.days)..now }

  around { |example| travel_to(now) { example.run } }

  def total!(device, country, clicks:, impressions:, position:)
    AhoyDashboard::SearchConsoleTotal.absorb([
      { date: day, device: device, country: country, clicks: clicks, impressions: impressions, ctr: 0.0,
        position: position }
    ])
  end

  def keyword!(device, date: day, clicks: 3)
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: date, query: "fci thomson", device: device, country: "usa", clicks: clicks, impressions: 30, ctr: 0.1,
        position: 4.0 }
    ])
  end

  before do
    total!("desktop", "usa", clicks: 10, impressions: 100, position: 2.0)
    total!("mobile", "usa", clicks: 30, impressions: 300, position: 6.0)
    total!("", "", clicks: 5, impressions: 100, position: 9.0)
  end

  it "folds every device and country of a day into one point on the chart" do
    result = described_class.call(range: range)
    point = sole_item(result.days)

    expect(point.clicks).to eq(45)
    expect(point.impressions).to eq(500)
    expect(point.ctr).to be_within(0.0001).of(0.09)
    expect(point.position).to be_within(0.0001).of(((2.0 * 100) + (6.0 * 300) + (9.0 * 100)) / 500)
  end

  it "reads one device alone and leaves rows without one out" do
    result = described_class.call(range: range, slice: AhoyDashboard::SearchConsole::Slice.new(device: "mobile"))

    expect(result.totals.clicks).to eq(30)
    expect(sole_item(result.days).position).to eq(6.0)
  end

  it "takes the last date from only the chart's range and slice, including an empty slice" do
    AhoyDashboard::SearchConsoleTotal.absorb([
      { date: day + 1, device: "desktop", country: "can", clicks: 3, impressions: 30, ctr: 0.1, position: 4.0 },
      { date: range.end.to_date + 1, device: "mobile", country: "usa", clicks: 3, impressions: 30, ctr: 0.1, position: 4.0 }
    ])

    mobile = described_class.call(range: range, slice: AhoyDashboard::SearchConsole::Slice.new(device: "mobile"))
    empty = described_class.call(range: range, slice: AhoyDashboard::SearchConsole::Slice.new(device: "tablet"))

    expect(mobile.last_date).to eq(day)
    expect(empty.last_date).to be_nil
  end

  it "draws one trend point per day however many devices the day was split over" do
    keyword!("desktop", clicks: 2)
    keyword!("mobile", clicks: 5)
    keyword!("mobile", date: day + 1, clicks: 1)

    row = sole_item(described_class.call(range: range).rows)

    expect(row.trend).to eq([ 7, 1 ])
  end
end
