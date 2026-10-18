require "rails_helper"

RSpec.describe "Dashboard Search Console backfill", type: :request do
  let(:path) { "/telemetry/settings/search_console_backfill" }

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "refuses while search console is switched off rather than saying it started" do
      allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: false, client_id: "cid", client_secret: "secret")
      create(:dash_google_account, :with_property)

      expect {
        post path
      }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::BackfillJob)

      expect(response).to redirect_to("/telemetry/settings/google_connection")
      expect(flash[:alert]).to eq(AhoyDashboard::SearchConsole::OFF_MESSAGE)
      expect(flash[:notice]).to be_nil
    end

    it "refuses when nothing is connected" do
      allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(true)
      expect {
        post path
      }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::BackfillJob)

      expect(response).to redirect_to("/telemetry/settings/google_connection")
      expect(flash[:alert]).to eq("Connect Google first.")
    end

    it "refuses when connected with no property picked" do
      allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(true)
      create(:dash_google_account)

      expect {
        post path
      }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::BackfillJob)

      expect(response).to redirect_to("/telemetry/settings/google_connection")
      expect(flash[:alert]).to eq("Pick a property first.")
    end

    it "queues the walk backwards once there is a property" do
      allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(true)
      create(:dash_google_account, :with_property)

      expect {
        post path
      }.to have_enqueued_job(AhoyDashboard::SearchConsole::BackfillJob)

      expect(response).to redirect_to("/telemetry/settings/google_connection")
      expect(flash[:notice]).to include("Reaching back")
    end
  end
end
