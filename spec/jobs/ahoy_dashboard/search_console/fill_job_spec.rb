require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe AhoyDashboard::SearchConsole::FillJob do
  let(:queue) { AhoyDashboard::SearchConsole::FillQueue }
  let(:url) { analytics_url }
  let(:days) { [ Date.new(2026, 7, 3), Date.new(2026, 7, 4), Date.new(2026, 7, 5) ] }

  def stub_days
    stub_request(:post, url).to_return(status: 200, body: analytics_body([]).to_json, headers: json_headers)
  end

  it "runs on the low queue, out of the way of anything somebody is waiting on" do
    expect(described_class.new.queue_name).to eq("low")
  end

  it "reports under its own name rather than a humanized key" do
    expect(described_class.schedule_key).to eq("search_console_fill")
    expect(AhoyDashboard::Schedule.find("search_console_fill").name).to eq("Search Console, filling gaps")
  end

  it "does nothing with nothing connected" do
    expect(AhoyDashboard::SearchConsole::FillCommand).not_to receive(:call)

    described_class.perform_now
  end

  it "does nothing while the integration is off" do
    search_console_disabled!
    create(:dash_google_account, :with_property)

    expect(AhoyDashboard::SearchConsole::FillCommand).not_to receive(:call)

    described_class.perform_now
  end

  describe "with a ready account" do
    before do
      search_console_enabled!
      create(:dash_google_account, :with_property, access_token: "good", expires_at: 30.minutes.from_now)
    end

    it "works through the whole queue rather than one day a run" do
      queue.start!(days)
      stub_days

      described_class.perform_now

      expect(queue.load.running?).to be(false)
    end

    it "stops and leaves the rest queued when Google stops answering" do
      queue.start!(days)
      stub_request(:post, url).to_return(status: 429, body: "quota", headers: json_headers)

      described_class.perform_now

      expect(queue.load.remaining).to eq(3)
    end

    it "records the run so the jobs screen can say how it went" do
      queue.start!([ Date.new(2026, 7, 3) ])
      stub_days

      described_class.perform_now

      expect(AhoyDashboard::JobRun.for("search_console_fill")).to have_attributes(status: "ok")
    end

    it "stops on an empty queue instead of looping" do
      described_class.perform_now

      expect(a_request(:post, url)).not_to have_been_made
    end
  end
end
