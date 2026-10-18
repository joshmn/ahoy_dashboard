require "rails_helper"

RSpec.describe "Dashboard single keyword checks", type: :request do
  def tracked!(**attributes)
    keyword = create(:dash_serp_keyword, **attributes)
    create(:dash_serp_keyword_target, keyword: keyword)
    keyword
  end

  describe "as an admin" do
    before do
      sign_in create(:user, :admin)
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
    end

    it "queues one check per place for that keyword alone, whether or not it is due" do
      keyword = tracked!(query: "botnet takedown", locations: %w[us gb], last_checked_at: Time.current)
      tracked!(query: "someone else", locations: %w[us])

      expect {
        post "/telemetry/settings/serp_keywords/#{keyword.id}/check"
      }.to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob).twice

      expect(AhoyDashboard::Serp::Keywords::CheckJob).to have_been_enqueued.with(keyword.id, "us")
      expect(AhoyDashboard::Serp::Keywords::CheckJob).to have_been_enqueued.with(keyword.id, "gb")
      expect(response).to redirect_to("/telemetry/settings/serp_keywords")
      expect(flash[:notice]).to eq("Checking botnet takedown from 2 places. Give it a minute, then reload.")
    end

    it "refuses a paused keyword" do
      keyword = tracked!(enabled: false)

      expect {
        post "/telemetry/settings/serp_keywords/#{keyword.id}/check"
      }.not_to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob)

      expect(flash[:alert]).to eq(AhoyDashboard::Serp::SweepCommand::PAUSED)
    end

    it "refuses a keyword with no site to look for" do
      keyword = create(:dash_serp_keyword)

      expect {
        post "/telemetry/settings/serp_keywords/#{keyword.id}/check"
      }.not_to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob)

      expect(flash[:alert]).to eq(AhoyDashboard::Serp::SweepCommand::NO_SITES)
    end

    it "refuses when the tracking is switched off" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
      keyword = tracked!

      post "/telemetry/settings/serp_keywords/#{keyword.id}/check"

      expect(flash[:alert]).to eq(AhoyDashboard::Serp::SweepCommand::OFF)
    end

    it "does not pay twice for a double press" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      keyword = tracked!(locations: %w[us])

      post "/telemetry/settings/serp_keywords/#{keyword.id}/check"

      expect {
        post "/telemetry/settings/serp_keywords/#{keyword.id}/check"
      }.not_to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob)

      expect(flash[:alert]).to eq(AhoyDashboard::Serp::SweepCommand::QUEUED)
    end

    it "skips a keyword just sent on its own when everything is checked" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      first = tracked!(query: "first", locations: %w[us])
      tracked!(query: "second", locations: %w[us])

      post "/telemetry/settings/serp_keywords/#{first.id}/check"

      expect {
        post "/telemetry/rank_check"
      }.to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob).once

      expect(flash[:notice]).to include("1 search")
    end
  end
end
