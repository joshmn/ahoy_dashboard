require "rails_helper"

RSpec.describe "Dashboard jobs", type: :request do
  def document
    Nokogiri::HTML5(response.body)
  end

  before do
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(false)
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/job_runs"

      expect(response).to redirect_to("/users/sign_in")
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "says why a job cannot run and where to fix it, instead of only disabling the button" do
      get "/telemetry/settings/job_runs"

      why = document.at_css("#jr-why-alerts")
      button = document.css("button[disabled]").find { |node| node["aria-describedby"] == "jr-why-alerts" }

      expect(why.text.squish).to include("No alert rules are switched on.")
      expect(why.at_css("a")["href"]).to eq("/telemetry/settings/alert_rules")
      expect(button).to be_present
    end

    it "links every job to its own page and keeps the run log off the list" do
      AhoyDashboard::JobRunEntry.create!(key: "backlinks", status: :ok, started_at: 2.hours.ago, finished_at: 2.hours.ago)

      get "/telemetry/settings/job_runs"

      expect(document.at_css(".jr-name[title='backlinks'] a")["href"]).to eq("/telemetry/settings/job_runs/backlinks")
      expect(document.at_css(".jr-log")).to be_nil
    end

    it "lists one job's runs on its own page, with how each went" do
      AhoyDashboard::JobRunEntry.create!(key: "backlinks", status: :ok, started_at: 2.hours.ago,
                                         finished_at: 2.hours.ago + 95.seconds)
      AhoyDashboard::JobRunEntry.create!(key: "alerts", status: :failed, started_at: 1.hour.ago,
                                         finished_at: 1.hour.ago + 2.seconds, error: "ArgumentError: no good\nline one")

      get "/telemetry/settings/job_runs/alerts"
      rows = document.css(".jr-log tbody tr:not(.jr-error)").map { |row| row.text.squish }

      expect(response).to have_http_status(:ok)
      expect(document.at_css("h1").text).to eq("Alert rules")
      expect(rows.size).to eq(1)
      expect(rows.first).to include("2s", "Failed")
      expect(document.at_css(".jr-log td details summary").text.strip).to eq("ArgumentError: no good")
      expect(document.at_css(".jr-log td details pre").text).to include("line one")
    end

    it "404s for a job nobody registered" do
      get "/telemetry/settings/job_runs/nope"

      expect(response).to have_http_status(:not_found)
    end

    it "says on the job's page why it cannot run" do
      get "/telemetry/settings/job_runs/alerts"

      why = document.at_css("#jr-why-alerts")
      button = document.css("button[disabled]").find { |node| node["aria-describedby"] == "jr-why-alerts" }

      expect(why.text.squish).to include("No alert rules are switched on.")
      expect(why.at_css("a")["href"]).to eq("/telemetry/settings/alert_rules")
      expect(button.text.strip).to eq("Run now")
    end

    it "pages through a long history" do
      51.times do |index|
        AhoyDashboard::JobRunEntry.create!(key: "backlinks", status: :ok, started_at: (index + 1).hours.ago,
                                           finished_at: (index + 1).hours.ago)
      end

      get "/telemetry/settings/job_runs/backlinks"
      expect(document.css(".jr-log tbody tr").size).to eq(50)
      expect(response.body).to include("1 to 50 of 51")

      get "/telemetry/settings/job_runs/backlinks", params: { page: 2 }
      expect(document.css(".jr-log tbody tr").size).to eq(1)
      expect(response.body).to include("51 to 51 of 51")
    end

    it "says the hourly rank check only sends what is due" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)

      get "/telemetry/settings/job_runs"
      row = document.css(".jr-job").find { |node| node.at_css(".jr-name[title='serp_dispatch']") }

      expect(row.at_css(".jr-why").text.squish).to eq(AhoyDashboard::Schedule.find("serp_dispatch").about)
    end

    it "says a run that never finished did not finish rather than still running" do
      AhoyDashboard::JobRunEntry.create!(key: "backlinks", status: :running, started_at: 1.day.ago)

      get "/telemetry/settings/job_runs/backlinks"

      expect(document.at_css(".jr-log tbody tr").text.squish).to include("Did not finish")
    end

    it "refuses to start a job that is off and says why" do
      post "/telemetry/settings/job_runs/alerts/run"

      expect(response).to redirect_to("/telemetry/settings/job_runs/alerts")
      expect(flash[:alert]).to eq("Alert rules is off. No alert rules are switched on.")
    end

    it "counts one start for a job started here" do
      create(:dash_alert_rule)

      post "/telemetry/settings/job_runs/alerts/run"

      expect(response).to redirect_to("/telemetry/settings/job_runs/alerts")
      expect(AhoyDashboard::JobRun.for("alerts")).to have_attributes(status: "running", runs_count: 1)
    end

    it "counts a start from the Check now button on Alerts" do
      create(:dash_alert_rule)

      post "/telemetry/seo/alert/runs"

      expect(AhoyDashboard::JobRun.for("alerts").runs_count).to eq(1)
      expect(AhoyDashboard::JobRun.for("alerts").last_run_at).to be_present
    end

    it "counts a backlinks sync from the Backlinks page as the day's sync" do
      allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
      allow(AhoyDashboard::Backlinks).to receive_messages(provider: :dataforseo, available?: true, refusal: nil)

      post "/telemetry/seo/backlink/syncs"

      expect(AhoyDashboard::JobRun.for("backlinks").runs_count).to eq(1)
      expect { AhoyDashboard::TickJob.perform_now }.not_to have_enqueued_job(AhoyDashboard::Backlinks::SyncJob)
    end
  end
end
