require "rails_helper"

RSpec.describe "Dashboard seo remembered range", type: :request do
  def range_button
    document.at_css("#tm-seo-period-button, #tm-rankings-period-button")
  end

  def seo_cookie
    cookies[AhoyDashboard::SeoRange::COOKIE]
  end

  before { sign_in create(:user, :admin) }

  it "opens the hub on the last 28 days when the dashboard remembered one day" do
    cookies[AhoyDashboard::BaseController::VIEW_COOKIE] = "period=day"

    get "/telemetry/seo"

    expect(response).to have_http_status(:ok)
    expect(range_button.text.squish).to eq("Last 28 days")
    expect(document.css("#tm-seo-period a[aria-current]").map { |link| link.text.squish }).to eq([ "Last 28 days" ])
  end

  it "ignores a one day range handed over in the URL" do
    get "/telemetry/seo", params: { period: "yesterday" }

    expect(range_button.text.squish).to eq("Last 28 days")
  end

  it "keeps a whole range handed over in the URL" do
    get "/telemetry/seo", params: { period: "30d" }

    expect(range_button.text.squish).to eq("Last 30 days")
  end

  it "remembers a range of its own, apart from the dashboard's" do
    get "/telemetry/seo", params: { period: "6mo" }

    expect(seo_cookie).to include("period=6mo")
    expect(cookies[AhoyDashboard::BaseController::VIEW_COOKIE]).to be_blank

    get "/telemetry/rankings"

    expect(range_button.text.squish).to eq("Last 6 months")
  end

  it "shows a week when asked but does not remember it" do
    get "/telemetry/seo", params: { period: "7d" }

    expect(range_button.text.squish).to eq("Last 7 days")
    expect(seo_cookie).to be_blank
  end

  it "offers no range shorter than a week" do
    get "/telemetry/seo"
    labels = document.css("#tm-seo-period a").map { |link| link.text.squish }

    expect(labels).to include("Last 7 days", "Last 28 days", "Last 30 days", "Custom range")
    expect(labels).not_to include("Realtime", "Today", "Yesterday")
  end

  it "carries no range between the dashboard and the SEO tab" do
    get "/telemetry/seo", params: { period: "6mo" }
    tabs = document.css("nav[aria-label=Primary] a").map { |link| [ link.text.squish, link["href"] ] }.to_h

    expect(tabs["Dashboard"]).to eq("/telemetry/")
    expect(tabs["Explore"]).to eq("/telemetry/explore")

    get "/telemetry/", params: { period: "day" }
    tabs = document.css("nav[aria-label=Primary] a").map { |link| [ link.text.squish, link["href"] ] }.to_h

    expect(tabs["SEO"]).to eq("/telemetry/seo")
  end

  it "widens an empty week with one button" do
    create(:dash_google_account, :with_property)
    allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(true)

    get "/telemetry/seo/brand_split", params: { period: "7d" }
    button = document.css("a").find { |link| link.text.squish == "Show the last 28 days" }

    expect(button["href"]).to eq("/telemetry/seo/brand_split?period=28d")
  end
end
