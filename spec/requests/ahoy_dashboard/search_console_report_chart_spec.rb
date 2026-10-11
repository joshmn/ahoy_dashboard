require "rails_helper"

RSpec.describe "Dashboard Search Console Performance chart", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before do
    sign_in create(:user, :admin)

    AhoyDashboard::SearchConsoleTotal.absorb([
      { date: now.to_date - 3, clicks: 30, impressions: 1_000, ctr: 0.03, position: 4.37 },
      { date: now.to_date - 2, clicks: 0, impressions: 0, ctr: 0.0, position: 0.0 },
      { date: now.to_date - 1, clicks: 45, impressions: 1_500, ctr: 0.03, position: 4.82 }
    ])
  end

  def chart
    Nokogiri::HTML5(response.body).at_css("[data-dash--chart-options-value]")
  end

  def format
    JSON.parse(chart["data-dash--chart-options-value"]).dig("library", "plugins", "tmFormat")
  end

  def points
    JSON.parse(chart["data-dash--chart-data-value"]).first["data"]
  end

  def values
    points.map(&:last)
  end

  it "names each measure after itself, never Visitors" do
    { "clicks" => "Clicks", "impressions" => "Impressions", "ctr" => "CTR", "position" => "Position" }
      .each do |measure, label|
        get "/telemetry/search_console_report", params: { measure: measure, period: "7d" }

        expect(format["label"]).to eq(label), "expected #{measure} to be labeled #{label}"
      end
  end

  it "keeps position to its decimals" do
    get "/telemetry/search_console_report", params: { measure: "position", period: "7d" }

    expect(format["value"]).to eq("decimal")
    expect(values.compact).to eq([ 4.37, 4.82 ])
  end

  it "draws click through rate as a percent rather than a fraction rounded to nothing" do
    get "/telemetry/search_console_report", params: { measure: "ctr", period: "7d" }

    expect(format["value"]).to eq("rate")
    expect(values.compact).to eq([ 3.0, 3.0 ])
  end

  it "leaves a day with no impressions out of the position and rate lines" do
    [ "position", "ctr" ].each do |measure|
      get "/telemetry/search_console_report", params: { measure: measure, period: "7d" }

      expect(values).to eq([ values.first, nil, values.last ]), "expected a gap in #{measure}"
      expect(format["missing"]).to eq("No impressions")
    end
  end

  it "draws clicks and impressions as whole counts" do
    get "/telemetry/search_console_report", params: { measure: "impressions", period: "7d" }

    expect(format["value"]).to eq("integer")
    expect(values).to eq([ 1_000, 0, 1_500 ])
  end

  it "keys the points by bare date so the browser's zone cannot move them" do
    get "/telemetry/search_console_report", params: { measure: "clicks", period: "7d" }

    expect(points.map(&:first)).to eq([ "2026-08-08", "2026-08-09", "2026-08-10" ])
    expect(format["interval"]).to eq("day")
  end

  it "labels the chart on the SEO overview the same way" do
    get "/telemetry/seo", params: { period: "7d" }

    expect(format).to include("label" => "Clicks", "value" => "integer")
  end
end
