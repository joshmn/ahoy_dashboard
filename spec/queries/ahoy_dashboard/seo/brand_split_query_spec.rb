require "rails_helper"

RSpec.describe AhoyDashboard::Seo::BrandSplitQuery do
  let(:today) { Date.new(2026, 8, 10) }
  let(:range) { (today - 6).beginning_of_day..today.end_of_day }

  def named!(query, clicks:, on: today)
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: on, query: query, clicks: clicks, impressions: clicks * 10, ctr: 0.1, position: 3.0 }
    ])
  end

  def totals!(clicks:, on: today)
    AhoyDashboard::SearchConsoleTotal.absorb([
      { date: on, clicks: clicks, impressions: clicks * 10, ctr: 0.1, position: 4.0 }
    ])
  end

  it "counts a search as brand when it contains any one of several terms, spaces and case aside" do
    named!("Federal Prison Dude reviews", clicks: 4)
    named!("federalprisondude consult", clicks: 3)
    named!("prison dude", clicks: 2)
    named!("halfway house rules", clicks: 7)

    result = described_class.call(range: range, terms: [ "federal prison dude", "Prison Dude" ])

    expect(result.brand.terms.map(&:query)).to match_array([ "Federal Prison Dude reviews", "federalprisondude consult", "prison dude" ])
    expect(result.other.terms.map(&:query)).to eq([ "halfway house rules" ])
    expect(result.brand.clicks).to eq(9)
    expect(result.other.clicks).to eq(7)
  end

  it "reads the total off the property and puts what Google did not name in a third figure" do
    named!("federal prison dude", clicks: 9)
    named!("halfway house rules", clicks: 7)
    totals!(clicks: 41)

    result = described_class.call(range: range, terms: [ "federal prison dude" ])

    expect(result.clicks).to eq(41)
    expect(result.named_clicks).to eq(16)
    expect(result.unnamed_clicks).to eq(25)
    expect(result.share_of(result.brand.clicks) + result.share_of(result.other.clicks) + result.share_of(result.unnamed_clicks)).to be_within(0.0001).of(1.0)
  end

  it "never reports a negative unnamed figure when the property total is missing" do
    named!("federal prison dude", clicks: 9)

    result = described_class.call(range: range, terms: [ "federal prison dude" ])

    expect(result.clicks).to eq(9)
    expect(result.unnamed_clicks).to eq(0)
  end

  it "falls back to the stored brand words when none are given" do
    AhoyDashboard::Setting.write(AhoyDashboard::Seo::BrandTerms::KEY, [ "halfway house" ])
    named!("halfway house rules", clicks: 7)
    named!("federal prison dude", clicks: 9)

    result = described_class.call(range: range)

    expect(result.terms).to eq([ "halfway house" ])
    expect(result.brand.terms.map(&:query)).to eq([ "halfway house rules" ])
  ensure
    AhoyDashboard::Setting.clear(AhoyDashboard::Seo::BrandTerms::KEY)
  end

  it "aggregates both day series in one read with unchanged chronology and zero-count days" do
    named!("brand% query", clicks: 4, on: today - 2)
    named!("other", clicks: 7, on: today - 2)
    named!("zero", clicks: 0, on: today - 1)
    named!("brand% latest", clicks: 2)
    named!("brand% future", clicks: 99, on: today + 1)
    sql = []
    subscriber = ->(_name, _started, _finished, _id, payload) do
      statement = payload[:sql]
      sql << statement if statement.include?("GROUP BY \"ahoy_dashboard_search_console_keywords\".\"date\"")
    end

    result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.call(range: range, terms: [ "brand%" ])
    end

    expect(result.points.map(&:to_h)).to eq([
      { on: today - 2, brand_clicks: 4, other_clicks: 7, brand_impressions: 40, other_impressions: 70 },
      { on: today - 1, brand_clicks: 0, other_clicks: 0, brand_impressions: 0, other_impressions: 0 },
      { on: today, brand_clicks: 2, other_clicks: 0, brand_impressions: 20, other_impressions: 0 }
    ])
    expect(sql.size).to eq(1)
  end

  it "keeps the device slice and places all searches on the other side when there are no brand terms" do
    allow(AhoyDashboard::Seo::BrandTerms).to receive(:current).and_return([])
    create(:dash_search_console_keyword, date: today, device: "mobile", country: "usa", clicks: 3, impressions: 30)
    create(:dash_search_console_keyword, date: today, device: "desktop", country: "usa", clicks: 99, impressions: 990)
    slice = AhoyDashboard::SearchConsole::Slice.new(device: "mobile")

    result = described_class.call(range: range, terms: [], slice: slice)

    expect(sole_item(result.points)).to have_attributes(brand_clicks: 0, other_clicks: 3, brand_impressions: 0, other_impressions: 30)
    expect(result.brand.clicks).to eq(0)
    expect(result.other.clicks).to eq(3)
  end
end
