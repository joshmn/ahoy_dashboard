require "rails_helper"

RSpec.describe "Dashboard seo stored Search Console rows", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 9, 19, 10, 0) }

  around { |example| travel_to(now) { example.run } }
  before { sign_in create(:user, :admin) }

  def document
    Nokogiri::HTML5(response.body)
  end

  def stored!
    (Date.new(2026, 7, 18)..Date.new(2026, 8, 18)).each do |on|
      AhoyDashboard::SearchConsoleTotal.absorb([ { date: on, clicks: 10, impressions: 100, ctr: 0.1, position: 5.0 } ])
      AhoyDashboard::SearchConsoleRow.absorb([
        { date: on, query: "federal prison consultant", page: "https://example.com/consult", clicks: 5, impressions: 50, ctr: 0.1, position: 2.0 }
      ])
    end
  end

  it "says what is stored and offers those dates when Google is not connected and the range is empty" do
    stored!

    get "/telemetry/search_console_report"
    button = document.css("a").find { |link| link.text.squish == "Show Jul 18 to Aug 18" }

    expect(response.body).to include("Nothing stored for these dates", "32 rows from Jul 18 to Aug 18")
    expect(response.body).not_to include("to get started")
    expect(button["href"]).to include("period=custom", "from=2026-07-18", "to=2026-08-18")
    expect(document.css("a").map { |link| link.text.squish }).to include("Connect Search Console")
  end

  it "does the same on the suite's own screens" do
    stored!

    get "/telemetry/seo/brand_split"

    expect(response.body).to include("Nothing stored for these dates")
    expect(document.css("a").find { |link| link.text.squish == "Show Jul 18 to Aug 18" }["href"]).to start_with("/telemetry/seo/brand_split?")
  end

  it "shows the stored rows once those dates are asked for" do
    stored!

    get "/telemetry/search_console_report", params: { period: "custom", from: "2026-07-18", to: "2026-08-18" }

    expect(response.body).not_to include("Nothing stored for these dates")
    expect(document.at_css(".sc-data-note").text).to include("Data runs through Aug 18")
  end

  it "still asks for a connection when nothing was ever stored" do
    get "/telemetry/search_console_report"

    expect(response.body).not_to include("Nothing stored for these dates")
    expect(response.body).to include("Search Console")
  end
end
