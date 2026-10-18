require "rails_helper"

RSpec.describe "Dashboard internal traffic", type: :request do
  let(:at) { dash_time(2026, 8, 10, 9) }

  def with_internal(list)
    AhoyDashboard::Preferences.write(:site, internal_ips: list)
    yield
  ensure
    AhoyDashboard::Preferences.clear(:site, :internal_ips)
  end

  before do
    sign_in create(:user, :admin)
    travel_to dash_time(2026, 8, 10, 12)

    dash_landing("/outside", at: at, visitor: "outside", ip: "203.0.113.10", country: "US")
    dash_landing("/inside", at: at, visitor: "inside", ip: "10.0.0.8", country: "US")
  end

  after { travel_back }

  it "leaves internal addresses out of the dashboard by default" do
    get "/telemetry/reports/pages", params: { period: "day" }

    expect(response.body).to include("/outside")
    expect(response.body).not_to include("/inside")
  end

  it "shows them when asked, the same way crawlers are" do
    get "/telemetry/reports/pages", params: { period: "day", internal: "1" }

    expect(response.body).to include("/outside")
    expect(response.body).to include("/inside")
  end

  it "offers the switch next to the crawlers one and carries it through links" do
    get "/telemetry", params: { period: "day" }
    open_palette
    expect(response.body).to include("Show hidden traffic")
    expect(response.body).to include(%(href="/telemetry/?internal=1&amp;period=day"))

    get "/telemetry", params: { period: "day", internal: "1" }
    open_palette
    expect(response.body).to include("Hide hidden traffic")
    expect(response.body).to include(%(href="/telemetry/?period=day"))
    expect(response.body).to include(%(href="/telemetry/exports/pages?internal=1&amp;period=day"))
  end

  it "does not offer the switch when nothing counts as internal" do
    with_internal([]) do
      get "/telemetry", params: { period: "day" }
      open_palette

      expect(response.body).not_to include("hidden traffic")
    end
  end

  it "counts everything when the list is empty" do
    with_internal([]) do
      get "/telemetry/reports/pages", params: { period: "day" }

      expect(response.body).to include("/inside")
    end
  end

  it "follows the switch in Explore and in an export" do
    get "/telemetry/explore", params: { period: "day", dimension: "page" }
    expect(response.body).to include("Include hidden traffic")
    expect(response.body).not_to include("Hidden traffic included")
    expect(response.body).not_to include("/inside")

    get "/telemetry/explore", params: { period: "day", dimension: "page", internal: "1" }
    expect(response.body).to include("Hidden traffic included")
    expect(response.body).to include("/inside")

    get "/telemetry/exports/pages", params: { period: "day" }
    expect(response.body).not_to include("/inside")

    get "/telemetry/exports/pages", params: { period: "day", internal: "1" }
    expect(response.body).to include("/inside")
  end

  it "never raises on a malformed address in the visits table" do
    broken = dash_landing("/broken", at: at, visitor: "broken", ip: "not.an.ip.at.all", country: "US")

    get "/telemetry/reports/pages", params: { period: "day" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("/broken")
  end

  it "says how many visits the switch is hiding, next to the switch" do
    get "/telemetry/explore", params: { period: "day", dimension: "page" }
    expect(response.body).to include("1 visit hidden<")
    expect(document.at_css("a[aria-label='Manage exclusions']")["href"])
      .to eq("/telemetry/settings/exclusions")

    get "/telemetry?loading=complete", params: { period: "day" }
    expect(response.body).to include("1 visit hidden<")
    expect(response.body).to include(%(href="/telemetry/?internal=1&amp;period=day">Show them))
    expect(document.at_css("a[aria-label='Manage exclusions']")["href"])
      .to eq("/telemetry/settings/exclusions")

    get "/telemetry/explore", params: { period: "day", dimension: "page", internal: "1" }
    expect(response.body).not_to include("Manage exclusions")
  end

  it "counts a visit an exclusion hides alongside the internal ones" do
    dash_landing("/elsewhere", at: at, visitor: "elsewhere", ip: "203.0.113.20", country: "DE")
    dash_exclusion("Germany", [ "country", "is", "DE" ])

    get "/telemetry?loading=complete", params: { period: "day" }

    expect(response.body).to include("2 visits hidden<")
  end

  it "says nothing when the switch is hiding nothing" do
    get "/telemetry/explore", params: { period: "yesterday", dimension: "page" }
    expect(response.body).not_to include("Manage exclusions")

    with_internal([]) do
      get "/telemetry?loading=complete", params: { period: "day" }
      expect(response.body).not_to include("Manage exclusions")
    end
  end
end
