require "rails_helper"

RSpec.describe "Dashboard excluded traffic, everywhere it reaches", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def exclude_datacenters!
    dash_exclusion("Datacenters", [ "asn", "contains", "DATACENTER" ])
  end

  def someone(token, at:, path: "/", **attributes)
    visit = dash_visit(started_at: at, visitor: token, **attributes)
    dash_page_view(visit, path: path, at: at)
    visit
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "leaves it out of the dashboard's own cards until the screen asks to see it" do
      exclude_datacenters!
      someone("bot", at: now - 1.hour, path: "/bot", asn: "BIG DATACENTER LLC")
      someone("reader", at: now - 1.hour, path: "/reader", asn: nil)

      get "/telemetry/reports/pages", params: { period: "day" }
      expect(response.body).to include("/reader")
      expect(response.body).not_to include("/bot")

      get "/telemetry/reports/pages", params: { period: "day", internal: "1" }
      expect(response.body).to include("/bot")
    end

    it "leaves it out of realtime, which never reads the switch" do
      exclude_datacenters!
      someone("bot", at: now - 1.minute, asn: "BIG DATACENTER LLC")
      someone("reader", at: now - 1.minute, asn: nil)

      get "/telemetry/realtime.json"
      expect(JSON.parse(response.body)).to eq("visitors" => 1)

      get "/telemetry/realtime.json", params: { internal: "1" }
      expect(JSON.parse(response.body)).to eq("visitors" => 1)
    end

    it "leaves it out of the visits on Search to conversion" do
      exclude_datacenters!
      on = now.to_date - 1
      AhoyDashboard::SearchConsoleTotal.absorb([ { date: on, clicks: 30, impressions: 300, ctr: 0.1, position: 2.0 } ])
      AhoyDashboard::SearchConsoleRow.absorb([
        { date: on, query: "federal prison consultant", page: "https://example.com/consult", clicks: 30,
          impressions: 300, ctr: 0.1, position: 2.0 }
      ])
      [ "BIG DATACENTER LLC", nil, "HOME BROADBAND" ].each do |asn|
        create(:ahoy_visit, :organic_search, started_at: now - 1.day, landing_page: "https://example.com/consult", asn: asn)
      end

      get "/telemetry/seo/conversion"
      row = document.css("tbody tr").find { |tr| tr.text.include?("/consult") }

      expect(row.css("td").map { |td| td.text.squish }[3]).to eq("2")
    end
  end
end
