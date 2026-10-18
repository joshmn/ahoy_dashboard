require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::FillJob do
  let(:queue) { AhoyDashboard::SearchConsole::FillQueue }
  let(:url) { analytics_url }
  let(:days) { [ Date.new(2026, 7, 3), Date.new(2026, 7, 4), Date.new(2026, 7, 5) ] }

  it "runs on the low queue, out of the way of anything somebody is waiting on" do
    expect(described_class.new.queue_name).to eq("low")
  end

  it "reports under its own name rather than a humanized key" do
    expect(described_class.schedule_key).to eq("search_console_fill")
    expect(AhoyDashboard::Schedule.find("search_console_fill").name).to eq("Search Console, filling gaps")
  end

  it "does nothing with nothing connected" do
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("search console fill skipped: search console is not configured")
    expect(AhoyDashboard::JobRun.for("search_console_fill").status).to eq("ok")
  end

  it "does nothing while the integration is off" do
    allow(Rails.logger).to receive(:info)
    search_console_disabled!
    create(:dash_google_account, :with_property)
    queue.start!(days)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("search console fill skipped: search console is not configured")
    expect(queue.load.remaining).to eq(3)
  end

  describe "with a ready account" do
    before do
      search_console_enabled!
      create(:dash_google_account, :with_property)
    end

    it "works through the whole queue rather than one day a run" do
      queue.start!(days)
      stub_analytics

      described_class.perform_now

      expect(queue.load.running?).to be(false)
    end

    it "stops and leaves the rest queued when Google stops answering" do
      queue.start!(days)
      stub_analytics_refusal(429, body: "quota")

      described_class.perform_now

      expect(queue.load.remaining).to eq(3)
    end

    it "records the run so the jobs screen can say how it went" do
      queue.start!([ Date.new(2026, 7, 3) ])
      stub_analytics

      described_class.perform_now

      expect(AhoyDashboard::JobRun.for("search_console_fill")).to have_attributes(status: "ok")
    end

    it "fails the run and keeps the day queued when Google does not answer" do
      queue.start!(days)
      stub_analytics_refusal(500)

      expect { described_class.perform_now }.to raise_error(AhoyDashboard::Job::Failed)

      expect(queue.load.remaining).to eq(3)
      expect(AhoyDashboard::JobRun.for("search_console_fill").status).to eq("failed")
    end

    it "stops on an empty queue instead of looping" do
      described_class.perform_now

      expect(a_request(:post, url)).not_to have_been_made
    end
  end
end
