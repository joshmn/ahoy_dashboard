require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::SearchConsoleKeywordQuery do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:keyword) { "fci thomson visiting" }

  around { |example| travel_to(now) { example.run } }

  def keyword!(date, clicks: 3, impressions: 50, ctr: 0.06, position: 8.0, query: keyword)
    create(:dash_search_console_keyword, date: date, query: query, clicks: clicks,
           impressions: impressions, ctr: ctr, position: position)
  end

  def range(days)
    (now - days.days)..now
  end

  it "gives every day in the window a row and marks the ones Google named" do
    keyword!(Date.new(2026, 8, 10), clicks: 4)
    keyword!(Date.new(2026, 8, 12), clicks: 6)

    result = described_class.call(keyword: keyword, range: range(30))

    expect(result.window).to eq(Date.new(2026, 8, 10)..Date.new(2026, 8, 12))
    expect(result.days.map(&:date)).to eq([ Date.new(2026, 8, 10), Date.new(2026, 8, 11), Date.new(2026, 8, 12) ])
    expect(result.days.map(&:recorded?)).to eq([ true, false, true ])
    expect(result.recorded_days.size).to eq(2)
  end

  it "trims the window to the days the keyword grain was pulled for" do
    keyword!(Date.new(2026, 8, 10))

    result = described_class.call(keyword: keyword, range: range(30))

    expect(result.requested.begin).to eq(Date.new(2026, 7, 21))
    expect(result.window).to eq(Date.new(2026, 8, 10)..Date.new(2026, 8, 10))
    expect(result).to be_trimmed
  end

  it "leaves a day with no row at zero clicks rather than inventing a position" do
    keyword!(Date.new(2026, 8, 10))
    keyword!(Date.new(2026, 8, 12))

    quiet = described_class.call(keyword: keyword, range: range(30)).days.second

    expect(quiet.clicks).to eq(0)
    expect(quiet.impressions).to eq(0)
    expect(quiet.position).to be_nil
    expect(quiet.ctr).to be_nil
  end

  it "weights the average position by impressions" do
    keyword!(Date.new(2026, 8, 10), impressions: 100, position: 4.0)
    keyword!(Date.new(2026, 8, 11), impressions: 300, position: 8.0)

    totals = described_class.call(keyword: keyword, range: range(30)).totals

    expect(totals.position).to eq(7.0)
  end

  it "works the click through rate out of the range rather than averaging the days" do
    keyword!(Date.new(2026, 8, 10), clicks: 1, impressions: 10, ctr: 0.1)
    keyword!(Date.new(2026, 8, 11), clicks: 1, impressions: 90, ctr: 0.011)

    totals = described_class.call(keyword: keyword, range: range(30)).totals

    expect(totals.clicks).to eq(2)
    expect(totals.impressions).to eq(100)
    expect(totals.ctr).to eq(0.02)
  end

  it "compares against the same length of time before the window" do
    (1..6).each { |day| keyword!(Date.new(2026, 8, day), clicks: 1) }
    (7..9).each { |day| keyword!(Date.new(2026, 8, day), clicks: 5) }

    result = described_class.call(keyword: keyword, range: Date.new(2026, 8, 7)..Date.new(2026, 8, 9))

    expect(result.window).to eq(Date.new(2026, 8, 7)..Date.new(2026, 8, 9))
    expect(result.previous_window).to eq(Date.new(2026, 8, 4)..Date.new(2026, 8, 6))
    expect(result.totals.clicks).to eq(15)
    expect(result.previous.clicks).to eq(3)
    expect(result).to be_comparable
  end

  it "offers no comparison when the window before it was never pulled" do
    keyword!(Date.new(2026, 8, 10))
    keyword!(Date.new(2026, 8, 11))

    result = described_class.call(keyword: keyword, range: range(30))

    expect(result.previous_window).to be_nil
    expect(result).not_to be_comparable
  end

  it "counts only its own keyword" do
    keyword!(Date.new(2026, 8, 10), clicks: 4)
    keyword!(Date.new(2026, 8, 10), clicks: 99, query: "halfway house rules")

    result = described_class.call(keyword: keyword, range: range(30))

    expect(result.totals.clicks).to eq(4)
  end

  it "reads the pages off the query and page grain" do
    keyword!(Date.new(2026, 8, 10))
    create(:dash_search_console_row, date: Date.new(2026, 8, 10), query: keyword,
           page: "https://example.com/a", clicks: 2, impressions: 20, position: 6.0)
    create(:dash_search_console_row, date: Date.new(2026, 8, 11), query: keyword,
           page: "https://example.com/a", clicks: 3, impressions: 30, position: 4.0)
    create(:dash_search_console_row, date: Date.new(2026, 8, 11), query: keyword,
           page: "https://example.com/b", clicks: 1, impressions: 10, position: 9.0)

    pages = described_class.call(keyword: keyword, range: range(30)).pages

    expect(pages.map(&:page)).to eq([ "https://example.com/a", "https://example.com/b" ])
    expect(pages.first.clicks).to eq(5)
    expect(pages.first.impressions).to eq(50)
    expect(pages.first.position).to eq(4.8)
  end

  it "says when the keyword was first and last recorded, whatever the range asks" do
    keyword!(Date.new(2026, 6, 1))
    keyword!(Date.new(2026, 8, 10))

    result = described_class.call(keyword: keyword, range: Date.new(2026, 8, 9)..Date.new(2026, 8, 11))

    expect(result.seen).to eq(Date.new(2026, 6, 1)..Date.new(2026, 8, 10))
  end

  it "answers with nothing rather than raising when the table is empty" do
    result = described_class.call(keyword: keyword, range: range(30))

    expect(result.window).to be_nil
    expect(result.covered).to be_nil
    expect(result.days).to be_empty
    expect(result.totals.clicks).to be_zero
    expect(result).not_to be_any
  end

  it "answers with nothing when the range sits outside what was pulled" do
    keyword!(Date.new(2026, 8, 10))

    result = described_class.call(keyword: keyword, range: Date.new(2026, 1, 1)..Date.new(2026, 1, 31))

    expect(result.window).to be_nil
    expect(result).to be_trimmed
    expect(result).not_to be_any
  end
end

RSpec.describe AhoyDashboard::SearchConsoleKeywordQuery, "by device and country" do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:keyword) { "fci thomson visiting" }
  let(:day) { Date.new(2026, 8, 12) }
  let(:range) { (now - 30.days)..now }

  around { |example| travel_to(now) { example.run } }

  before do
    create(:dash_search_console_keyword, date: day, query: keyword, device: "desktop", country: "usa",
           clicks: 6, impressions: 100, position: 2.0)
    create(:dash_search_console_keyword, date: day, query: keyword, device: "mobile", country: "usa",
           clicks: 2, impressions: 300, position: 10.0)
  end

  it "folds a day split across devices into one day, weighting position by impressions" do
    result = described_class.call(keyword: keyword, range: range)
    stored = sole_item(result.recorded_days)

    expect(stored.clicks).to eq(8)
    expect(stored.impressions).to eq(400)
    expect(stored.ctr).to be_within(0.0001).of(0.02)
    expect(stored.position).to eq(8.0)
  end

  it "reads one device alone" do
    result = described_class.call(keyword: keyword, range: range,
                                  slice: AhoyDashboard::SearchConsole::Slice.new(device: "desktop"))

    expect(result.totals.clicks).to eq(6)
    expect(sole_item(result.recorded_days).position).to eq(2.0)
  end

  it "says when a keyword was seen for the slice, not for the whole record" do
    create(:dash_search_console_keyword, date: day - 5, query: keyword, device: "tablet", country: "usa")

    result = described_class.call(keyword: keyword, range: range,
                                  slice: AhoyDashboard::SearchConsole::Slice.new(device: "mobile"))

    expect(result.seen).to eq(day..day)
    expect(result.covered.begin).to eq(day - 5)
  end
end
