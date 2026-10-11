require "rails_helper"
require "support/ahoy_dashboard/fixtures"
require "support/ahoy_dashboard/search_console"

RSpec.describe "Dashboard search console keyword", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:keyword) { "fci thomson visiting" }
  let(:path) { "/telemetry/search_console_keyword?q=#{CGI.escape(keyword)}" }

  around { |example| travel_to(now) { example.run } }

  def keyword!(date, clicks: 3, impressions: 50, ctr: 0.06, position: 8.0, query: keyword)
    create(:dash_search_console_keyword, date: date, query: query, clicks: clicks,
           impressions: impressions, ctr: ctr, position: position)
  end

  def history!
    (1..12).each { |day| keyword!(Date.new(2026, 8, day), clicks: day, impressions: day * 20) }
  end

  # The chart element carries its series and its options as data rather than
  # printing a script beside itself, so the payload is read back off the element.
  def chart_payload(name)
    element = Nokogiri::HTML5(response.body).at_css('[data-controller~="dash--chart"]')

    JSON.parse(element["data-dash--chart-#{name}-value"])
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get path

      expect(response).to redirect_to("/users/sign_in")
    end

    it "does not admit that it exists to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "sends somebody with no keyword to look up back to the performance page" do
      get "/telemetry/search_console_keyword"

      expect(response).to redirect_to(%r{/telemetry/search_console_report})
    end

    it "renders the keyword, its figures and its days" do
      history!

      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(keyword)
      expect(response.body).to include("Clicks")
      expect(response.body).to include("Average position")
      expect(response.body).to include("Every day it showed up")
      expect(response.body).to include("Aug 1, 2026 to Aug 12, 2026")
      expect(response.body).to include("About this data")
      expect(response.body).not_to include("August")
    end

    it "draws clicks by default and switches series on the query string" do
      history!

      get path

      expect(chart_payload("data").first["name"]).to eq("Clicks")
      expect(chart_payload("options").dig("library", "plugins", "tmFormat", "label")).to eq("Clicks")

      get "#{path}&series=position"

      expect(chart_payload("options").dig("library", "plugins", "tmFormat", "label")).to eq("Average position")
      expect(chart_payload("options").dig("library", "scales", "y", "reverse")).to be(true)
    end

    it "falls back to clicks when the series is nonsense" do
      history!

      get "#{path}&series=vibes"

      expect(response).to have_http_status(:ok)
      expect(chart_payload("options").dig("library", "plugins", "tmFormat", "label")).to eq("Clicks")
    end

    it "says the record is shorter than the range that was asked for" do
      keyword!(Date.new(2026, 8, 10))

      get path

      expect(response.body).to include("The keyword record runs")
      expect(response.body).to include("never pulled at this grain")
    end

    it "says nothing was pulled at this grain when the table is empty" do
      create(:dash_google_account, :with_property)

      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing pulled at the keyword grain yet")
    end

    it "asks for Google to be connected when nothing is connected or pulled" do
      get path

      expect(response.body).to include("Connect Google Search Console to get started",
                                       "/telemetry/settings/google_connection")
    end

    it "keeps the pages this keyword landed on apart from the keyword numbers" do
      history!
      create(:dash_search_console_row, date: Date.new(2026, 8, 10), query: keyword,
             page: "https://example.com/resources/federal-prisons/thomson", clicks: 2, impressions: 20)

      get path

      expect(response.body).to include("Where it landed")
      expect(response.body).to include("They add up to less than the clicks above")

      landing = Nokogiri::HTML5(response.body).css("a.seo-link").find { |link| link.text.include?("/resources/federal-prisons/thomson") }

      expect(landing).to be_present
      expect(landing["href"]).to start_with("/telemetry")
      expect(CGI.unescape(landing["href"])).to include("/resources/federal-prisons/thomson")
    end

    it "answers as json" do
      history!

      get "#{path}&series=impressions", headers: { "Accept" => "application/json" }

      payload = response.parsed_body

      expect(payload["keyword"]).to eq(keyword)
      expect(payload["series"]).to eq("impressions")
      expect(payload["totals"]["clicks"]).to eq(78)
      expect(payload["days"].size).to eq(12)
    end

    it "carries the range from the card it was opened from" do
      history!

      get "#{path}&period=7d"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Last 7 days")
    end

    it "links to the tracked keyword whatever case it was tracked in" do
      history!
      tracked = create(:dash_serp_keyword, query: "FCI Thomson Visiting")

      get path

      expect(response.body).to include("See rankings", "/telemetry/rank_keyword?keyword=#{tracked.id}")
    end

    it "offers no date range shorter than a day of Search Console data" do
      history!

      get path

      expect(response.body).to match(%r{/telemetry/search_console_keyword\?[^"]*period=7d})
      expect(response.body).not_to match(%r{/telemetry/search_console_keyword\?[^"]*period=(realtime|day|yesterday)(&|")})
    end
  end

  describe "the links into it" do
    before { sign_in create(:user, :admin) }

    it "hangs off every query row on the card but not off a page row" do
      search_console_disabled!
      create(:dash_google_account, :with_property)
      create(:dash_search_console_row, date: Date.new(2026, 8, 18), query: keyword,
             page: "https://example.com/a", clicks: 4, impressions: 40)

      get "/telemetry/search_console"

      expect(response.body).to include("q=fci+thomson+visiting")

      get "/telemetry/search_console?tab=pages"

      expect(response.body).not_to include("/telemetry/search_console_keyword?")
    end

    it "hangs off the query column on the stored rows screen" do
      create(:dash_search_console_row, date: Date.new(2026, 8, 18), query: keyword,
             page: "https://example.com/a", clicks: 4, impressions: 40)

      get "/telemetry/settings/search_console_rows"

      expect(response.body).to include("/telemetry/search_console_keyword?q=")
    end
  end
end

RSpec.describe "Dashboard search console keyword by device and country", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:keyword) { "fci thomson visiting" }
  let(:day) { Date.new(2026, 8, 12) }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def document
    Nokogiri::HTML5(response.body)
  end

  def stored!
    [ [ "desktop", "usa", 6 ], [ "mobile", "usa", 3 ], [ "mobile", "gbr", 1 ], [ "", "", 4 ] ].each do |device, country, clicks|
      create(:dash_search_console_keyword, date: day, query: keyword, device: device, country: country,
             clicks: clicks, impressions: clicks * 10, position: 5.0)
      create(:dash_search_console_row, date: day, query: keyword, page: "https://example.com/#{device.presence || "old"}",
             device: device, country: country, clicks: clicks, impressions: clicks * 10)
      AhoyDashboard::SearchConsoleTotal.absorb([
        { date: day, device: device, country: country, clicks: clicks, impressions: clicks * 10, ctr: 0.1, position: 5.0 }
      ])
    end
  end

  def show(**params)
    get "/telemetry/search_console_keyword", params: { q: keyword, **params }
  end

  it "renders both menus next to the date range" do
    stored!

    show

    expect(document.css("#tm-sc-device a").map { |link| link.text.strip }).to include("All devices", "Mobile")
    expect(document.css("#tm-sc-country a").map { |link| link.text.strip })
      .to eq([ "All countries", "United States", "United Kingdom" ])
  end

  it "sums every device and country of a day into one day, old rows included" do
    stored!

    show(format: :json)
    payload = response.parsed_body

    expect(payload["days"].size).to eq(1)
    expect(payload["days"].first["clicks"]).to eq(14)
    expect(payload["totals"]["clicks"]).to eq(14)
    expect(payload["device"]).to be_nil
  end

  it "narrows the days, the totals and the pages to one device" do
    stored!

    show(device: "mobile", format: :json)
    payload = response.parsed_body

    expect(payload["device"]).to eq("mobile")
    expect(payload["days"].first["clicks"]).to eq(4)
    expect(payload["pages"].map { |page| page["page"] }).to eq([ "https://example.com/mobile" ])
  end

  it "narrows to one country" do
    stored!

    show(country: "usa", format: :json)

    expect(response.parsed_body["country"]).to eq("usa")
    expect(response.parsed_body["totals"]["clicks"]).to eq(9)
  end

  it "ignores a device it does not know" do
    stored!

    show(device: "phone", format: :json)

    expect(response.parsed_body["device"]).to be_nil
    expect(response.parsed_body["totals"]["clicks"]).to eq(14)
  end

  it "carries the slice on the period and measure links" do
    stored!

    show(device: "mobile", country: "usa")
    links = [ *document.css("#tm-keyword-period a"), *document.css("nav[aria-label='Which measure the chart draws'] a") ]

    expect(links).not_to be_empty
    expect(links.map { |link| Rack::Utils.parse_query(URI(link["href"]).query) })
      .to all(include("device" => "mobile", "country" => "usa", "q" => keyword))
  end

  it "sends a missing keyword back to Performance with the slice kept" do
    get "/telemetry/search_console_keyword", params: { device: "mobile" }

    expect(Rack::Utils.parse_query(URI(response.location).query)).to include("device" => "mobile")
  end

  it "opens the dialog from Performance with the slice on the link" do
    stored!

    get "/telemetry/search_console_report", params: { device: "mobile" }
    link = document.css("tbody tr .sc-label a").first

    expect(Rack::Utils.parse_query(URI(link["href"]).query)).to include("device" => "mobile", "view" => "details")
  end

  it "says a picked device has nothing yet rather than saying google never named the keyword" do
    create(:dash_search_console_keyword, date: day, query: keyword, clicks: 4)

    show(device: "tablet")

    expect(response.body).to include("Nothing in this range for Tablet.")
    expect(response.body).not_to include("Google never named this keyword")
    reset = document.css("a").find { |link| link.text.strip == "Show all devices and countries" }
    expect(Rack::Utils.parse_query(URI(reset["href"]).query)).not_to include("device")
  end
end
