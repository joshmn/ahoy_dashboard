require "rails_helper"

RSpec.describe "Dashboard AI visibility Run now", type: :request do
  let(:path) { "/telemetry/seo/ai_visibility/runs" }

  before { allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(true) }

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "asks every prompt of every keyed assistant" do
      create(:dash_ai_assistant, :keyed, name: "openai")
      create(:dash_ai_assistant, :keyed, name: "anthropic")
      create_list(:dash_ai_prompt, 3)

      expect { post path }.to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob).exactly(6).times

      expect(response).to redirect_to("/telemetry/seo/ai_visibility")
      expect(flash[:notice]).to include("6 questions")
      expect(AhoyDashboard::AiVisibility::Run.last).to be_triggered_by_manual
    end

    it "refuses while it is off" do
      allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(false)

      post path

      expect(flash[:alert]).to eq("AI visibility is off. Turn it on under Settings, Features.")
    end

    it "refuses with no keyed assistant" do
      create(:dash_ai_prompt)

      post path

      expect(flash[:alert]).to include("No assistant is on with a key")
    end

    it "refuses with no prompts" do
      create(:dash_ai_assistant, :keyed)

      post path

      expect(flash[:alert]).to include("There are no prompts")
    end

    it "sends nothing when the run would not fit the cap, and says how many are needed and left" do
      create(:dash_ai_assistant, :keyed)
      create_list(:dash_ai_prompt, 3)
      AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 2)

      expect { post path }.not_to have_enqueued_job

      expect(flash[:alert]).to include("A run needs 3 requests and 2 are left this month.")
    end
  end
end
