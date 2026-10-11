require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard excluded traffic, everywhere it reaches", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def document
    Nokogiri::HTML5(response.body)
  end

  def exclude_datacenters!
    AhoyDashboard::Exclusion.create!(name: "Datacenters",
                                     filters: [ { "dimension" => "asn", "operator" => "contains", "value" => "DATACENTER" } ])
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

  it "leaves it out of the numbers in the traffic email" do
    window = AhoyDashboard::Reports::Digests::Window.new(period: :daily, starts_on: Date.new(2026, 8, 10),
                                                          ends_on: Date.new(2026, 8, 10))
    someone("bot", at: dash_time(2026, 8, 10, 9), path: "/bot", asn: "BIG DATACENTER LLC")
    someone("reader", at: dash_time(2026, 8, 10, 9), path: "/reader", asn: nil)
    someone("neighbor", at: dash_time(2026, 8, 10, 9), path: "/reader", asn: "HOME BROADBAND")

    expect(dash_value(AhoyDashboard::Reports::DigestQuery.call(window: window).stats, "visitors")).to eq(3)

    exclude_datacenters!
    result = AhoyDashboard::Reports::DigestQuery.call(window: window)

    expect(dash_value(result.stats, "visitors")).to eq(2)
    expect(result.list(:pages).rows.map(&:label)).to eq([ "/reader" ])
  end

  it "leaves it out of the traffic the alerts watch" do
    finish = now.beginning_of_hour
    someone("history", at: finish - 40.days)
    someone("bot", at: finish - 30.minutes, asn: "BIG DATACENTER LLC")
    someone("reader", at: finish - 30.minutes, asn: nil)

    expect(AhoyDashboard::Alerts::TrafficQuery.call(now: now).hour.visitors).to eq(2)

    exclude_datacenters!

    expect(AhoyDashboard::Alerts::TrafficQuery.call(now: now).hour.visitors).to eq(1)
  end

  describe "the assistant" do
    before do
      someone("bot", at: now - 1.day, asn: "BIG DATACENTER LLC")
      someone("reader", at: now - 1.day, asn: nil)
      exclude_datacenters!
    end

    def visitors(answer)
      answer[:figures]["visitors"][:value]
    end

    it "reads around it and says what hid it" do
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new.execute(days: 7)

      expect(visitors(answer)).to eq(1)
      expect(answer[:hidden_traffic]).to eq("excluded")
      expect(answer[:hidden_by]).to include("Datacenters")
    end

    it "reads it when the screen the question came from was showing it" do
      slice = AhoyDashboard::Assistant::Slice.from_context("slice" => { "filters" => "none", "internal" => true })
      answer = AhoyDashboard::Assistant::Tools::TrafficSummary.new(slice: slice).execute(days: 7)

      expect(visitors(answer)).to eq(2)
      expect(answer[:hidden_traffic]).to eq("shown")
      expect(answer).not_to have_key(:hidden_by)
    end

    it "carries the switch in the slice it saves and the window it reads" do
      shown = AhoyDashboard::QueryForm.from_params({ internal: "1" })
      slice = AhoyDashboard::Assistant::Slice.from_context("slice" => AhoyDashboard::Assistant::Slice.snapshot(shown))

      expect(AhoyDashboard::Assistant::Window.call(period: "7d", slice: slice).to_h[:hidden_traffic]).to eq("shown")
      expect(AhoyDashboard::Assistant::Window.call(period: "7d").to_h).to include(hidden_traffic: "excluded")
    end
  end
end
