# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Precomputed dashboard responses", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }

  include_context "with a memory cache"

  around { |example| travel_to(now) { example.run } }

  before do
    AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago", precomputed_dashboard: true)
    sign_in(create(:user, :admin))
    visit = dash_visit(started_at: now - 2.days, visitor: "original", country: "US")
    dash_page_view(visit, path: "/original", at: visit.started_at)
    get("/telemetry?loading=complete", params: { period: "30d" })
  end

  def add_traffic
    2.times do |index|
      visit = dash_visit(started_at: Time.current, visitor: "new-#{index}", country: "CA")
      dash_page_view(visit, path: "/new", at: Time.current)
    end
  end

  def visitor_count
    document.at_css("button[name='metric'][value='visitors'] .tile-value").text.strip
  end

  it "serves the previous analytical reading while a refresh is queued" do
    travel(31.seconds)
    add_traffic

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(visitor_count).to eq("1")
  end

  it "keeps realtime current while serving a previous analytical reading" do
    travel(31.seconds)
    add_traffic

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(document.at_css("tm-frame#dash_realtime").text.squish).to include("2 live")
  end

  it "retains the calculation timestamp until the snapshot is replaced" do
    timestamp = document.at_css("#dash-snapshot-freshness time")["datetime"]
    travel(31.seconds)

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(document.at_css("#dash-snapshot-freshness time")["datetime"]).to eq(timestamp)
  end

  it "exposes the calculation timestamp with an explicit UTC offset" do
    expect(document.at_css("#dash-snapshot-freshness time")["datetime"]).to eq("2026-08-11T09:30:00-05:00")
  end

  it "displays the full timestamp in the dashboard time zone" do
    expect(document.at_css("#dash-snapshot-freshness").text.squish)
      .to eq("Snapshot updated Aug 11, 2026 at 9:30:00 AM CDT")
  end

  it "does not repeat the expensive session or journey aggregates on a stale hit" do
    travel(31.seconds)
    statements = captured_sql(/grouping sets|tm_journey/i, cached: true) do
      get("/telemetry?loading=complete", params: { period: "30d" })
    end

    expect(statements).to be_empty
  end

  it "uses the current filtered readings instead of the unfiltered snapshot" do
    travel(31.seconds)
    add_traffic

    get("/telemetry?loading=complete", params: { period: "30d", filters: [
      { dimension: "country", operator: "is", value: "CA" }
    ] })

    expect(visitor_count).to eq("2")
  end

  it "omits snapshot freshness for a live filtered response" do
    get("/telemetry?loading=complete", params: { period: "30d", filters: [
      { dimension: "country", operator: "is", value: "CA" }
    ] })

    expect(document.at_css("#dash-snapshot-freshness")).to be_nil
  end

  it "respects a default segment created after the unfiltered snapshot" do
    travel(31.seconds)
    add_traffic
    create(:dash_segment, applied_by_default: true,
      filters: [{ "dimension" => "country", "operator" => "is", "value" => "CA" }])

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(visitor_count).to eq("2")
  end

  it "keeps JSON chart requests on the ordinary analytical path" do
    travel(31.seconds)
    add_traffic

    get("/telemetry/dashboard.json", params: { period: "30d" })

    expect(JSON.parse(response.body).fetch("stats").find { |stat| stat["key"] == "visitors" }.fetch("display")).to eq("3")
  end

  it "returns to the ordinary path as soon as the flag is disabled" do
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: false)
    travel(31.seconds)
    add_traffic

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(visitor_count).to eq("3")
  end

  it "recomputes rather than serving a snapshot older than five minutes" do
    travel(301.seconds)
    add_traffic

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(visitor_count).to eq("3")
  end
end
