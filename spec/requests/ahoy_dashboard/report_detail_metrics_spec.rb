# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Dashboard report detail metrics", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before do
    sign_in(create(:user, :admin))
    first = dash_visit(started_at: now - 1.day, visitor: "first", country: "US")
    second = dash_visit(started_at: now - 1.day, visitor: "second", country: "CA")
    dash_page_view(first, path: "/a")
    dash_page_view(second, path: "/a")
    3.times { dash_page_view(first, path: "/b") }
    dash_goal(first, AhoyDashboard::ENGAGEMENT, path: "/a", scroll_depth: 40, engagement_time: 30)
    dash_goal(second, AhoyDashboard::ENGAGEMENT, path: "/a", scroll_depth: 80, engagement_time: 90)
  end

  def visible_rows
    document.css(".data-row").map do |row|
      [row.at_css(".nm").text, row.css(".cnt").map(&:text)]
    end
  end

  it "keeps visitor counts and ordering in the HTML details list" do
    get("/telemetry/reports/pages", params: {view: "details"})

    expect(visible_rows).to eq([["/a", ["2"]], ["/b", ["1"]]])
  end

  it "does not aggregate engagement for an HTML list that only shows visitors" do
    statements = analytics_sql { get("/telemetry/reports/pages", params: {view: "details"}) }

    expect(statements.join(" ")).not_to match(/scroll_depth|engagement_time/)
  end

  it "treats a request that accepts anything as the HTML list it gets back" do
    statements = analytics_sql { get("/telemetry/reports/pages", params: { view: "details" }, headers: { "Accept" => "*/*" }) }

    expect(response.media_type).to eq("text/html")
    expect(visible_rows).to eq([ [ "/a", [ "2" ] ], [ "/b", [ "1" ] ] ])
    expect(statements.join(" ")).not_to match(/scroll_depth|engagement_time/)
  end

  it "does not aggregate session duration for visitor counts grouped by country" do
    statements = analytics_sql { get("/telemetry/reports/locations", params: {view: "details"}) }

    expect(statements.join(" ")).not_to include("max(ahoy_events.time)")
  end

  it "retains all metric values in JSON details" do
    get("/telemetry/reports/pages.json", params: {view: "details"})
    row = JSON.parse(response.body).fetch("rows").find { |entry| entry.fetch("value") == "/a" }

    expect(row.fetch("metrics")).to eq("visitors" => 2, "pageviews" => 2, "bounce_rate" => 50.0,
      "scroll_depth" => 60.0, "engagement_time" => 60)
  end

  it "retains the full detail reading in CSV exports" do
    get("/telemetry/exports/pages")
    row = CSV.parse(response.body).find { |entry| entry.first == "/a" }

    expect(row.drop(1).map(&:to_f)).to eq([2.0, 2.0, 50.0, 60.0, 60.0])
  end

  context "with a registered report whose primary detail metric is pageviews" do
    before do
      tab = AhoyDashboard::Report::Tab.new(key: "reading", label: "Reading", dimension_key: "page",
        metrics: %w[visitors pageviews], detail_metrics: %w[pageviews visitors scroll_depth], label_column: "Page")
      AhoyDashboard::Report.register(key: "reading", title: "Reading", tabs: [tab])
    end

    it "keeps the configured primary metric and its ordering in HTML details" do
      get("/telemetry/reports/reading", params: {view: "details"})

      expect(visible_rows).to eq([["/b", ["3"]], ["/a", ["2"]]])
    end

    it "continues rendering every configured column on the HTML card" do
      get("/telemetry/reports/reading")

      expect(visible_rows).to eq([["/a", ["2", "2"]], ["/b", ["1", "3"]]])
    end
  end
end
