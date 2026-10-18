require "rails_helper"

RSpec.describe "Dashboard seo device and country", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }
  let(:on) { now.to_date - 2 }
  let(:key) { AhoyDashboard::Seo::BrandTerms::KEY }
  let(:query) { "federal prison consultant" }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def metrics(clicks, impressions, position: 4.0)
    { clicks: clicks, impressions: impressions, ctr: clicks.to_f / impressions, position: position }
  end

  def stored!
    AhoyDashboard::SearchConsoleTotal.absorb([
      { date: on, device: "", country: "", **metrics(100, 1_000) },
      { date: on, device: "mobile", country: "usa", **metrics(30, 300) },
      { date: on, device: "desktop", country: "gbr", **metrics(20, 200) }
    ])
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: on, query: query, device: "", country: "", **metrics(100, 1_000, position: 6.0) },
      { date: on, query: query, device: "mobile", country: "usa", **metrics(30, 300, position: 6.0) },
      { date: on, query: query, device: "desktop", country: "gbr", **metrics(20, 200, position: 6.0) }
    ])
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: on, query: query, page: "https://example.com/consult", device: "", country: "", **metrics(60, 600) },
      { date: on, query: query, page: "https://example.com/", device: "", country: "", **metrics(40, 400) },
      { date: on, query: query, page: "https://example.com/consult", device: "mobile", country: "usa", **metrics(30, 300) },
      { date: on, query: query, page: "https://example.com/consult", device: "desktop", country: "gbr", **metrics(20, 200) }
    ])
  end

  def tile_value(label)
    node = document.css("[class*=tile]").find { |tile| tile.text.squish.start_with?(label) }
    node && node.text.squish.delete_prefix(label).strip.split(" ").first
  end

  def menu_links(section)
    frame = { "Device" => "tm-sc-device", "Country" => "tm-sc-country", "Date range" => "tm-seo-period" }.fetch(section)

    document.css("##{frame} a")
  end

  def href_params(href)
    Rack::Utils.parse_query(URI(href).query.to_s)
  end

  reports = {
    "Opportunities" => "/telemetry/seo/opportunity",
    "Cannibalization" => "/telemetry/seo/cannibalization",
    "Brand vs. non-brand" => "/telemetry/seo/brand_split",
    "Search to conversion" => "/telemetry/seo/conversion"
  }.freeze

  reports.each do |name, path|
    describe name do
      it "offers every device and every country with rows in the range" do
        stored!

        get path

        expect(response).to have_http_status(:ok)
        expect(menu_links("Device").map { |link| link.text.squish }).to eq([ "All devices", "Desktop", "Mobile", "Tablet" ])
        expect(menu_links("Country").map { |link| link.text.squish }).to eq([ "All countries", "United States", "United Kingdom" ])
      end

      it "marks the picked device and country as current" do
        stored!

        get path, params: { device: "mobile", country: "usa" }

        expect(menu_links("Device").find { |link| link["aria-current"] == "true" }.text.squish).to eq("Mobile")
        expect(menu_links("Country").find { |link| link["aria-current"] == "true" }.text.squish).to eq("United States")
      end

      it "keeps the device and country on the date range links" do
        stored!

        get path, params: { device: "mobile", country: "usa" }

        periods = menu_links("Date range")
        expect(periods).not_to be_empty
        expect(periods.map { |link| href_params(link["href"]).values_at("device", "country") }.uniq).to eq([ %w[mobile usa] ])
      end

      it "keeps the other choice when one menu changes" do
        stored!

        get path, params: { device: "mobile", country: "usa" }

        desktop = menu_links("Device").find { |link| link.text.squish == "Desktop" }
        everywhere = menu_links("Country").find { |link| link.text.squish == "All countries" }

        expect(href_params(desktop["href"]).values_at("device", "country")).to eq(%w[desktop usa])
        expect(href_params(everywhere["href"])).to include("device" => "mobile")
        expect(href_params(everywhere["href"])).not_to have_key("country")
      end

      it "ignores a device or country it does not know" do
        stored!

        get path, params: { device: "toaster", country: "united states" }

        expect(response).to have_http_status(:ok)
        expect(menu_links("Device").find { |link| link["aria-current"] == "true" }.text.squish).to eq("All devices")
        expect(menu_links("Country").find { |link| link["aria-current"] == "true" }.text.squish).to eq("All countries")
      end
    end
  end

  it "counts rows from before the split under all devices, and drops them once a device is picked" do
    stored!
    AhoyDashboard::Setting.write(key, [ "federal prison consultant" ])

    get "/telemetry/seo/brand_split"
    expect(tile_value("Clicks")).to eq("150")

    get "/telemetry/seo/brand_split", params: { device: "mobile" }
    expect(tile_value("Clicks")).to eq("30")

    get "/telemetry/seo/brand_split", params: { country: "gbr" }
    expect(tile_value("Clicks")).to eq("20")

    get "/telemetry/seo/brand_split", params: { device: "mobile", country: "gbr" }
    expect(tile_value("Clicks")).to be_nil
    expect(response.body).to include("Nothing to split in this range")
    expect(document.text.squish).to include("Nothing in this range for Mobile in United Kingdom.")
    expect(document.text.squish).not_to include("Nothing stored for these dates")

    show_all = document.css("a").find { |link| link.text.squish == "Show all devices and countries" }
    expect(URI(show_all["href"]).path).to eq("/telemetry/seo/brand_split")
    expect(href_params(show_all["href"]).keys).not_to include("device", "country")
  end

  it "says the numbers are one device and country instead of the whole property" do
    stored!

    get "/telemetry/seo/opportunity"
    expect(document.text.squish).to include("Clicks and impressions are Google's totals for the property.")

    get "/telemetry/seo/opportunity", params: { device: "mobile", country: "usa" }
    expect(document.text.squish).to include("Showing Mobile in United States only.")
    expect(document.text.squish).not_to include("Google's totals for the property")
  end

  it "narrows Google's total on Search to conversion" do
    stored!

    get "/telemetry/seo/conversion"
    expect(tile_value("Search clicks")).to eq("150")

    get "/telemetry/seo/conversion", params: { device: "desktop" }
    expect(tile_value("Search clicks")).to eq("20")
  end

  it "narrows the clicks on Opportunities" do
    stored!

    get "/telemetry/seo/opportunity"
    expect(tile_value("Clicks on these searches")).to eq("150")

    get "/telemetry/seo/opportunity", params: { device: "mobile" }
    expect(tile_value("Clicks on these searches")).to eq("30")
  end

  it "only finds two pages on one search where the picked device had both" do
    stored!

    get "/telemetry/seo/cannibalization"
    expect(tile_value("Contested")).to eq("1")

    get "/telemetry/seo/cannibalization", params: { device: "mobile" }
    expect(tile_value("Contested")).to be_nil
    expect(response.body).to include("No competing pages in this range")
  end

  it "carries the device and country to a search's own page" do
    stored!

    get "/telemetry/seo/opportunity", params: { device: "mobile", country: "usa" }

    link = document.css("a").find { |node| node.text.squish == query }
    expect(link).to be_present
    expect(URI(link["href"]).path).to eq("/telemetry/search_console_keyword")
    expect(href_params(link["href"])).to include("q" => query, "device" => "mobile", "country" => "usa")
  end

  it "keeps the device and country through saving brand words" do
    stored!

    get "/telemetry/seo/brand_split", params: { device: "mobile", country: "usa" }

    action = document.css("form").find { |form| form["action"].to_s.include?("/seo/brand_terms") }["action"]
    expect(href_params(action)).to include("device" => "mobile", "country" => "usa")

    patch action, params: { brand_terms: { terms: "consultant" } }

    expect(response).to redirect_to(%r{/telemetry/seo/brand_split\?})
    expect(href_params(response.location)).to include("device" => "mobile", "country" => "usa")
  end

  it "leaves the rank reports without the menus" do
    stored!

    get "/telemetry/seo/visibility", params: { device: "mobile", country: "usa" }

    expect(response).to have_http_status(:ok)
    expect(menu_links("Device")).to be_empty
    expect(menu_links("Country")).to be_empty
    expect(document.css("a[href*='device=']")).to be_empty
  end

  it "leaves the overview without the menus" do
    stored!

    get "/telemetry/seo", params: { device: "mobile" }

    expect(response).to have_http_status(:ok)
    expect(menu_links("Device")).to be_empty
  end
end
