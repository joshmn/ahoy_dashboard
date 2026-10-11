require "rails_helper"

RSpec.describe "Dashboard job run times", type: :request do
  def document
    Nokogiri::HTML5(response.body)
  end

  before do
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(false)
    sign_in create(:user, :admin)
  end

  def cadence_of(key)
    row = document.css("tr").find { |tr| tr.at_css("[title='#{key}']") }
    row.css("td")[1].text.squish
  end

  it "prints the Search Console run in the dashboard's own time zone with the reason" do
    entry = AhoyDashboard::Schedule::ALL.find { |candidate| candidate.key == "search_console_ingest" }
    local = entry.window_start(Time.current).in_time_zone(AhoyDashboard.time_zone).strftime("%-l:%M %p")

    get "/telemetry/settings/job_runs"

    expect(cadence_of("search_console_ingest")).to eq("Daily, #{local}, after Google closes its day")
    expect(response.body).not_to include("Los Angeles")
  end

  it "prints a daily job in the dashboard's zone with no reason when it has none" do
    get "/telemetry/settings/job_runs"

    expect(cadence_of("alert_digest")).to eq("Daily, 7:00 AM")
  end
end
