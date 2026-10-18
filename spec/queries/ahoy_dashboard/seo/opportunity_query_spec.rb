require "rails_helper"

RSpec.describe AhoyDashboard::Seo::OpportunityQuery do
  let(:today) { Date.new(2026, 8, 10) }
  let(:range) { (today - 6).beginning_of_day..today.end_of_day }
  let(:query) { "halfway house rules" }

  def keyword!(device:, country:, clicks:, impressions:)
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: today, query: query, device: device, country: country, clicks: clicks, impressions: impressions,
        ctr: clicks.to_f / impressions, position: 9.0 }
    ])
  end

  def row!(page, device:, country:, clicks:)
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: today, query: query, page: page, device: device, country: country, clicks: clicks,
        impressions: clicks * 10, ctr: 0.1, position: 9.0 }
    ])
  end

  it "names the page with the most clicks summed across devices and countries, not the biggest single row" do
    keyword!(device: "mobile", country: "usa", clicks: 20, impressions: 400)
    row!("https://example.com/a", device: "mobile", country: "usa", clicks: 9)
    row!("https://example.com/b", device: "mobile", country: "usa", clicks: 6)
    row!("https://example.com/b", device: "desktop", country: "usa", clicks: 6)

    expect(sole_item(described_class.call(range: range).rows).page).to eq("https://example.com/b")
  end

  it "reads only the picked device and country, and leaves rows with neither out" do
    keyword!(device: "", country: "", clicks: 50, impressions: 900)
    keyword!(device: "mobile", country: "usa", clicks: 20, impressions: 400)
    keyword!(device: "desktop", country: "can", clicks: 5, impressions: 100)
    row!("https://example.com/a", device: "desktop", country: "can", clicks: 5)
    row!("https://example.com/b", device: "mobile", country: "usa", clicks: 20)

    all = described_class.call(range: range)
    mobile = described_class.call(range: range, slice: AhoyDashboard::SearchConsole::Slice.new(device: "mobile"))
    canada = described_class.call(range: range, slice: AhoyDashboard::SearchConsole::Slice.new(country: "can"))

    expect(all.clicks).to eq(75)
    expect(mobile.clicks).to eq(20)
    expect(sole_item(mobile.rows).page).to eq("https://example.com/b")
    expect(canada.clicks).to eq(5)
    expect(sole_item(canada.rows).page).to eq("https://example.com/a")
  end

  def search!(text, clicks:, impressions:, position:)
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: today, query: text, device: "", country: "", clicks: clicks, impressions: impressions,
        ctr: clicks.to_f / impressions, position: position }
    ])
  end

  it "reads the tiles and side lists over every search, not only the ones with the most upside" do
    search!("fci thomson", clicks: 5, impressions: 2_000, position: 12.0)
    search!("federal prison consultant", clicks: 1, impressions: 1_000, position: 2.0)

    result = described_class.call(range: range, limit: 1)

    expect(result.rows.map(&:query)).to eq([ "fci thomson" ])
    expect(result.under_performing.map(&:query)).to include("federal prison consultant")
    expect(result.clicks).to eq(6)
    expect(result.impressions).to eq(3_000)
  end

  it "keeps representative pages for the full result even when the displayed list is limited" do
    search!(query, clicks: 5, impressions: 2_000, position: 12.0)
    search!("without a recorded page", clicks: 1, impressions: 1_000, position: 14.0)
    row!("https://example.com/z", device: "mobile", country: "usa", clicks: 5)
    row!("https://example.com/a", device: "mobile", country: "usa", clicks: 5)

    result = described_class.call(range: range, limit: 1)
    striking = result.striking.index_by(&:query)

    expect(result.rows.size).to eq(1)
    expect(striking.size).to eq(2)
    expect(striking.fetch(query).page).to eq("https://example.com/a")
    expect(striking.fetch("without a recorded page").page).to be_nil
    expect(result.impressions).to eq(3_000)
  end

  it "reads the range once however many lists and tiles the page asks for" do
    search!("fci thomson", clicks: 5, impressions: 2_000, position: 12.0)
    search!("federal prison consultant", clicks: 1, impressions: 1_000, position: 2.0)
    statements = captured_sql("ahoy_dashboard_search_console_keywords", cached: true) do
      result = described_class.call(range: range)
      [ result.rows, result.striking(limit: 20), result.under_performing(limit: 15), result.clicks,
        result.impressions, result.upside, result.striking_count, result.under_performing_count ]
    end

    expect(statements.count { |sql| sql.include?("GROUP BY") }).to eq(1)
  end

  it "orders the below expected list by the shortfall, then by upside, impressions and the search" do
    search!("short by a lot", clicks: 0, impressions: 2_000, position: 5.0)
    search!("short by less, less upside", clicks: 50, impressions: 4_000, position: 8.0)
    search!("short by less, more upside", clicks: 34, impressions: 4_000, position: 9.0)
    search!("short by less, same again", clicks: 50, impressions: 4_000, position: 8.0)
    search!("on target", clicks: 300, impressions: 3_000, position: 4.0)

    result = described_class.call(range: range)

    expect(result.under_performing.map(&:query))
      .to eq([ "short by a lot", "short by less, more upside", "short by less, less upside", "short by less, same again" ])
    expect(result.under_performing.map(&:expected)).to eq([ 104, 96, 112, 112 ])
    expect(result.under_performing_count).to eq(4)
  end

  it "adds the tiles up over every qualifying search, rounded the way the list is" do
    search!("fci thomson", clicks: 5, impressions: 2_000, position: 12.04)
    search!("federal prison consultant", clicks: 1, impressions: 1_000, position: 2.0)
    search!("too quiet to count", clicks: 1, impressions: 20, position: 15.0)

    result = described_class.call(range: range)

    expect([ result.clicks, result.impressions, result.upside, result.striking_count ]).to eq([ 6, 3_000, 197, 1 ])
    expect(result.rows.map(&:position)).to eq([ 12.0, 2.0 ])
  end

  it "keeps striking distance and the band column on the same positions" do
    search!("page one search", clicks: 1, impressions: 500, position: 7.0)
    search!("second page search", clicks: 1, impressions: 500, position: 14.0)
    search!("tenth and a bit", clicks: 1, impressions: 500, position: 10.4)

    rows = described_class.call(range: range).rows.index_by(&:query)

    expect(rows["page one search"].band).to eq("Page one")
    expect(rows["page one search"]).not_to be_striking
    expect(rows["second page search"].band).to eq("Striking distance")
    expect(rows["second page search"]).to be_striking
    expect(rows["tenth and a bit"].band).to eq("Striking distance")
    expect(rows["tenth and a bit"]).to be_striking
  end
end
