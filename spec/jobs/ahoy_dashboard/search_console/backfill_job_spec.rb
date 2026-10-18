require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::BackfillJob do
  before { allow(Rails.logger).to receive(:info) }

  it "runs on the low queue, behind the fresh window rather than in front of it" do
    expect(described_class.new.queue_name).to eq("low")
  end

  include_examples "a search console account job", "backfill"

  it "does nothing without a property" do
    search_console_enabled!
    create(:dash_google_account)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("search console backfill skipped: google is not connected")
  end

  describe "with a ready account" do
    let!(:account) { create(:dash_google_account, :with_property) }

    before { search_console_enabled! }

    it "walks a slice of history back for it" do
      stub_analytics

      described_class.perform_now

      expect(account.reload.backfilled_to).to be_present
      expect(AhoyDashboard::JobRun.for("search_console_backfill").status).to eq("ok")
    end
  end
end
