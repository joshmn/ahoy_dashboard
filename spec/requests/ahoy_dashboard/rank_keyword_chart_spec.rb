require "rails_helper"

RSpec.describe "Dashboard rank keyword chart", type: :request do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:now) { ActiveSupport::TimeZone["America/Chicago"].local(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:keyword) { create(:dash_serp_keyword, query: "visiting hours") }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def reading(at:, position:)
    run = create(:dash_serp_run, keyword: keyword, location: "us", checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    create(:dash_serp_check, run: run, keyword: keyword, site: site, target: target, location: "us",
           checked_at: at, position: position, url: "https://example.com/page")
  end

  def open_keyword(**params)
    get "/telemetry/rank_keyword", params: { q: keyword.query, **params }
    follow_redirect! while response.redirect?
  end

  it "hands the chart a check the site was missing from as a gap, not a dropped point" do
    reading(at: now - 4.days, position: 8)
    reading(at: now - 3.days, position: 6)
    reading(at: now - 2.days, position: nil)
    reading(at: now - 1.day, position: 4)

    open_keyword

    expect(dash_chart_points.map(&:last)).to eq([ 8, 6, nil, 4 ])
    expect(dash_chart_plugin("tmFormat")["missing"]).to eq("Not in the results")
  end

  it "places the points by date, so a long wait between checks reads as one" do
    reading(at: now - 20.days, position: 8)
    reading(at: now - 3.days, position: 6)
    reading(at: now - 2.days, position: 5)

    open_keyword(period: "30d")

    expect(dash_chart_plugin("tmFormat")["scale"]).to eq("time")
    expect(dash_chart_points.map(&:first)).to eq([
      "2026-07-31T09:00:00-05:00", "2026-08-17T09:00:00-05:00", "2026-08-18T09:00:00-05:00"
    ])
  end

  it "stamps each check in the dashboard's zone rather than the app's" do
    reading(at: now - 3.days, position: 8)
    reading(at: now - 2.days, position: 6)
    reading(at: now - 1.day, position: 4)

    open_keyword

    expect(dash_chart_points.map(&:first)).to all(end_with("-05:00"))
    expect(dash_chart_points.first.first).to eq("2026-08-17T09:00:00-05:00")
  end

  it "leaves the readings as text below three ranked readings however many misses there were" do
    reading(at: now - 3.days, position: 8)
    reading(at: now - 2.days, position: nil)
    reading(at: now - 1.day, position: 4)

    open_keyword

    expect(dash_chart).to be_nil
    expect(response.body).to include("The chart starts at the third.")
  end
end
