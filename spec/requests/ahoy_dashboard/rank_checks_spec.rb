require "rails_helper"

RSpec.describe "Dashboard rank checks", type: :request do
  describe "gating" do
    it "sends a signed out visitor to sign in" do
      post "/telemetry/rank_check"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      post "/telemetry/rank_check"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "refuses when the tracking is switched off" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)

      post "/telemetry/rank_check"

      expect(response).to redirect_to("/telemetry/rankings")
      expect(flash[:alert]).to eq(AhoyDashboard::Serp::SweepCommand::OFF)
    end

    it "refuses when nothing is tracked" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)

      post "/telemetry/rank_check"

      expect(response).to redirect_to("/telemetry/rankings")
      expect(flash[:alert]).to eq(AhoyDashboard::Serp::SweepCommand::NOTHING)
    end

    it "queues one check per search and place, whether or not it is due" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
      keyword = create(:dash_serp_keyword, locations: %w[us gb],
                       last_checked_at: Time.current)
      create(:dash_serp_keyword_target, keyword: keyword)

      expect {
        post "/telemetry/rank_check"
      }.to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob).twice

      expect(response).to redirect_to("/telemetry/rankings")
      expect(flash[:notice]).to include("2 searches")
    end
  end
end
