require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::IngestJob do
  before { allow(Rails.logger).to receive(:info) }

  def run_of
    AhoyDashboard::JobRun.for("search_console_ingest")
  end

  it "runs on the low queue" do
    expect(described_class.new.queue_name).to eq("low")
  end

  include_examples "a search console account job", "ingest"

  it "does nothing without a property, because there is nothing to ask about" do
    search_console_enabled!
    create(:dash_google_account)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("search console ingest skipped: no search console property is selected")
  end

  describe "with a ready account" do
    let!(:account) { create(:dash_google_account, :with_property) }

    before { search_console_enabled! }

    it "pulls the window for it" do
      stub_analytics

      described_class.perform_now

      expect(account.reload.synced_at).to be_present
      expect(run_of.status).to eq("ok")
    end

    it "leaves the run ok when Google only says the quota is spent" do
      allow(Rails.logger).to receive(:warn)
      stub_analytics_refusal(429)

      described_class.perform_now

      expect(Rails.logger).to have_received(:warn).with(/search console ingest hit a quota/)
      expect(run_of.status).to eq("ok")
    end
  end
end
