require "rails_helper"

RSpec.describe AhoyDashboard::Seo::ConversionQuery do
  let(:today) { AhoyDashboard.time_zone.local(2026, 8, 10, 12) }
  let(:range) { (today - 6.days).beginning_of_day..today.end_of_day }

  def row!(query, page, device: "mobile", country: "usa", clicks: 5)
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: today.to_date, query: query, page: page, device: device, country: country, clicks: clicks,
        impressions: clicks * 10, ctr: 0.1, position: 5.0 }
    ])
  end

  def visit!(device_type:, country:, page: "https://example.com/consult")
    create(:ahoy_visit, :organic_search, started_at: today - 1.hour, landing_page: page,
                                         device_type: device_type, country: country)
  end

  def slice(**choice)
    AhoyDashboard::SearchConsole::Slice.new(**choice)
  end

  it "names the search with the most clicks summed across devices and countries, not the biggest single row" do
    row!("fci thomson", "https://example.com/consult", device: "mobile", clicks: 9)
    row!("thomson prison", "https://example.com/consult", device: "mobile", clicks: 6)
    row!("thomson prison", "https://example.com/consult", device: "desktop", clicks: 6)

    expect(sole_item(described_class.call(range: range).rows).query).to eq("thomson prison")
  end

  it "breaks top-search ties by impressions and then query after normalizing page URLs" do
    row!("zeta", "https://example.com/consult/", clicks: 6)
    row!("alpha", "https://example.com/consult?source=search", clicks: 6)
    row!("higher clicks", "https://example.com/other", clicks: 7)

    rows = described_class.call(range: range).rows.index_by(&:path)

    expect(rows.fetch("/consult").query).to eq("alpha")
    expect(rows.fetch("/other").query).to eq("higher clicks")
  end

  it "counts visits on every device and in every country when nothing is picked" do
    row!("fci thomson", "https://example.com/consult")
    visit!(device_type: "Desktop", country: "US")
    visit!(device_type: "mobile", country: "US")
    visit!(device_type: "mobile", country: "CA")

    expect(sole_item(described_class.call(range: range).rows).visits).to eq(3)
  end

  it "narrows the visits to the picked device whatever case ahoy stored it in" do
    row!("fci thomson", "https://example.com/consult", device: "desktop")
    visit!(device_type: "Desktop", country: "US")
    visit!(device_type: "desktop", country: "US")
    visit!(device_type: "mobile", country: "US")

    expect(sole_item(described_class.call(range: range, slice: slice(device: "desktop")).rows).visits).to eq(2)
  end

  it "narrows the visits to the picked country, matching Google's three letters to ahoy's two" do
    row!("fci thomson", "https://example.com/consult", country: "can")
    visit!(device_type: "mobile", country: "CA")
    visit!(device_type: "mobile", country: "US")

    result = described_class.call(range: range, slice: slice(device: "mobile", country: "can"))

    expect(sole_item(result.rows).visits).to eq(1)
  end

  it "narrows the conversions to the same visits" do
    row!("fci thomson", "https://example.com/consult")
    create(:dash_goal, event_name: "consult_booked")
    [ [ "mobile", "US" ], [ "desktop", "US" ] ].each do |device_type, country|
      visit = visit!(device_type: device_type, country: country)
      create(:ahoy_event, visit: visit, name: "consult_booked", time: visit.started_at + 1.minute)
    end

    all = sole_item(described_class.call(range: range).rows)
    mobile = sole_item(described_class.call(range: range, slice: slice(device: "mobile")).rows)

    expect([ all.conversions, all.converting ]).to eq([ 2, 2 ])
    expect([ mobile.visits, mobile.conversions, mobile.converting ]).to eq([ 1, 1, 1 ])
  end

  it "leaves out search rows from before device and country were stored once one is picked" do
    row!("fci thomson", "https://example.com/consult", device: "", country: "", clicks: 40)
    row!("fci thomson", "https://example.com/consult", device: "mobile", country: "usa", clicks: 5)

    expect(described_class.call(range: range).clicks).to eq(45)
    expect(described_class.call(range: range, slice: slice(device: "mobile")).clicks).to eq(5)
  end

  it "counts a visit that completes two goals as one conversion, so the rate cannot pass 100%" do
    row!("fci thomson", "https://example.com/consult")
    create(:dash_goal, event_name: "consult_booked")
    create(:dash_goal, event_name: "guide_downloaded")
    visit = visit!(device_type: "mobile", country: "US")
    create(:ahoy_event, visit: visit, name: "consult_booked", time: visit.started_at + 1.minute)
    create(:ahoy_event, visit: visit, name: "guide_downloaded", time: visit.started_at + 2.minutes)

    result = described_class.call(range: range)

    expect(sole_item(result.rows).conversions).to eq(1)
    expect(sole_item(result.rows).goals.values.sum).to eq(2)
    expect(result.conversions).to eq(1)
    expect(result.rate).to eq(1.0)
  end

  it "leaves out visits from crawlers" do
    row!("fci thomson", "https://example.com/consult")
    create(:page_view_event, :crawler, visit: visit!(device_type: "desktop", country: "US"))
    create(:page_view_event, visit: visit!(device_type: "desktop", country: "US"))

    expect(sole_item(described_class.call(range: range).rows).visits).to eq(1)
  end

  it "counts human goals on mixed visits once and excludes crawler goals and visits outside the range" do
    row!("fci thomson", "https://example.com/consult")
    create(:dash_goal, event_name: "consult_booked")
    mixed = visit!(device_type: "desktop", country: "US")
    create(:page_view_event, :crawler, visit: mixed, time: today)
    2.times { create(:ahoy_event, visit: mixed, name: "consult_booked", time: today, properties: {}) }
    crawler = visit!(device_type: "desktop", country: "US")
    create(:ahoy_event, visit: crawler, name: "consult_booked", time: today, properties: { crawler: "Bot" })
    earlier = create(:ahoy_visit, :organic_search, started_at: range.begin - 1.hour,
                                                landing_page: "https://example.com/consult")
    create(:ahoy_event, visit: earlier, name: "consult_booked", time: today, properties: {})

    result = sole_item(described_class.call(range: range).rows)

    expect(result.visits).to eq(1)
    expect(result.converting).to eq(1)
    expect(result.goals.values).to eq([ 1 ])
  end

  it "does not count a goal completed after the range ends" do
    row!("fci thomson", "https://example.com/consult")
    create(:dash_goal, event_name: "consult_booked")
    visit = create(:ahoy_visit, :organic_search, started_at: range.end - 10.minutes, landing_page: "https://example.com/consult")
    create(:ahoy_event, visit: visit, name: "consult_booked", time: range.end + 1.hour)

    row = sole_item(described_class.call(range: range).rows)

    expect(row.visits).to eq(1)
    expect([ row.conversions, row.converting ]).to eq([ 0, 0 ])
  end

  it "matches visits to Google's page when only one of them has a trailing slash" do
    row!("fci thomson", "https://example.com/consult/")
    visit!(device_type: "desktop", country: "US", page: "https://example.com/consult")
    visit!(device_type: "desktop", country: "US", page: "https://example.com/consult/?ref=nav")

    row = sole_item(described_class.call(range: range).rows)

    expect(row.path).to eq("/consult")
    expect(row.visits).to eq(2)
  end

  it "weighs the position of a path across every url Google reported for it" do
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: today.to_date, query: "fci thomson", page: "https://example.com/consult?utm_source=x", device: "", country: "",
        clicks: 2, impressions: 100, ctr: 0.02, position: 2.0 },
      { date: today.to_date, query: "fci thomson", page: "https://www.example.com/consult", device: "", country: "",
        clicks: 1, impressions: 300, ctr: 0.003, position: 10.0 }
    ])

    row = sole_item(described_class.call(range: range).rows)

    expect(row.clicks).to eq(3)
    expect(row.impressions).to eq(400)
    expect(row.position).to eq(8.0)
  end

  describe "hidden traffic" do
    before do
      row!("fci thomson", "https://example.com/consult")
      create(:dash_goal, event_name: "consult_booked")
    end

    def converted!(**attributes)
      visit = create(:ahoy_visit, :organic_search, started_at: today - 1.hour,
                                                   landing_page: "https://example.com/consult", **attributes)
      create(:ahoy_event, visit: visit, name: "consult_booked", time: visit.started_at + 1.minute)
    end

    it "leaves out a visit a saved exclusion hides, and its conversion with it" do
      AhoyDashboard::Exclusion.create!(name: "Datacenters",
                                       filters: [ { "dimension" => "asn", "operator" => "contains", "value" => "DATACENTER" } ])
      converted!(asn: "BIG DATACENTER LLC")
      converted!(asn: nil)
      converted!(asn: "HOME BROADBAND")

      row = sole_item(described_class.call(range: range).rows)

      expect([ row.visits, row.conversions, row.converting ]).to eq([ 2, 2, 2 ])
    end

    it "leaves out internal addresses, which it used to count" do
      converted!(ip: "10.0.0.8")
      converted!

      row = sole_item(described_class.call(range: range).rows)

      expect([ row.visits, row.conversions ]).to eq([ 1, 1 ])
    end
  end

  describe "shared visit and goal population" do
    let(:result) { sole_item(described_class.call(range: range).rows) }

    before do
      row!("consult", "https://example.com/consult")
      create(:dash_goal, event_name: "consult_booked")
      create(:dash_goal, event_name: "guide_downloaded")
      converted = visit!(device_type: "mobile", country: "US")
      other = visit!(device_type: "mobile", country: "US")
      other.update!(visitor_token: converted.visitor_token)
      2.times { create(:ahoy_event, visit: converted, name: "consult_booked", time: today) }
      create(:ahoy_event, visit: converted, name: "guide_downloaded", time: today)
    end

    it "counts sessions independently from their matching events" do
      expect(result.visits).to eq(2)
    end

    it "counts a returning visitor once across converted and unconverted sessions" do
      expect(result.visitors).to eq(1)
    end

    it "counts a session completing several goals once" do
      expect(result.converting).to eq(1)
    end

    it "deduplicates repeated events for each goal" do
      expect(result.goals).to eq("consult_booked" => 1, "guide_downloaded" => 1)
    end

    it "excludes paid search sessions and their matching goals" do
      paid = create(:ahoy_visit, :paid_search, started_at: today, landing_page: "https://example.com/consult")
      create(:ahoy_event, visit: paid, name: "consult_booked", time: today)

      expect([result.visits, result.converting]).to eq([2, 1])
    end

    it "preserves visits with human activity outside the range without counting crawler goals" do
      mixed = visit!(device_type: "mobile", country: "US")
      create(:page_view_event, visit: mixed, time: range.end + 1.hour)
      create(:ahoy_event, visit: mixed, name: "consult_booked", time: today, properties: { crawler: "Bot" })

      expect([result.visits, result.converting]).to eq([3, 1])
    end

    it "does not require a matching goal to count sessions when no goals are defined" do
      AhoyDashboard::Goal.delete_all

      expect([result.visits, result.converting, result.goals]).to eq([2, 0, {}])
    end

    it "leaves unrelated landing paths outside the selected search pages" do
      unrelated = visit!(device_type: "mobile", country: "US", page: "https://example.com/other")
      create(:ahoy_event, visit: unrelated, name: "consult_booked", time: today)

      expect([result.visits, result.converting]).to eq([2, 1])
    end
  end
end
