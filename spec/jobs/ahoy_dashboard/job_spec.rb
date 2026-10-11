require "rails_helper"

RSpec.describe AhoyDashboard::Job do
  include ActiveJob::TestHelper

  before do
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(false)
  end

  def run_of(key)
    AhoyDashboard::JobRun.for(key)
  end

  describe "a scheduled job started from somewhere other than the tick" do
    it "records the start the moment it is enqueued" do
      AhoyDashboard::Alerts::RunJob.perform_later

      expect(run_of("alerts")).to have_attributes(status: "running", runs_count: 1)
      expect(run_of("alerts").last_run_at).to be_within(5.seconds).of(Time.current)
    end

    it "counts one start when the enqueued job then runs" do
      perform_enqueued_jobs { AhoyDashboard::Alerts::RunJob.perform_later }

      expect(run_of("alerts")).to have_attributes(status: "ok", runs_count: 1)
    end

    it "records the start of a job a host's own cron runs inline" do
      AhoyDashboard::Alerts::RunJob.perform_now

      expect(run_of("alerts")).to have_attributes(status: "ok", runs_count: 1)
      expect(run_of("alerts").last_run_at).to be_present
    end

    it "keeps the tick from starting it again straight after" do
      allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
      allow(AhoyDashboard::Backlinks).to receive_messages(provider: :dataforseo, available?: true)

      AhoyDashboard::Backlinks::SyncJob.perform_later

      expect { AhoyDashboard::TickJob.perform_now }.not_to have_enqueued_job(AhoyDashboard::Backlinks::SyncJob)
      expect(run_of("backlinks").runs_count).to eq(1)
    end

    it "does not write a row for a job the schedule does not know" do
      expect { AhoyDashboard::Serp::Keywords::CheckJob.perform_later(1, "us") }
        .not_to change(AhoyDashboard::JobRun, :count)
    end
  end

  describe "a job enqueued again to retry" do
    it "does not count as another start" do
      job = AhoyDashboard::Alerts::RunJob.new
      job.enqueue
      job.executions = 1
      job.enqueue

      expect(run_of("alerts").runs_count).to eq(1)
    end
  end
end
