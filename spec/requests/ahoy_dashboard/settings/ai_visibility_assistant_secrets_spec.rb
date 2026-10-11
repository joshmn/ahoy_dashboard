require "rails_helper"
require "support/ahoy_dashboard/ai_visibility_settings"

RSpec.describe "Dashboard AI visibility key removal", type: :request do
  let(:path) { "/telemetry/settings/ai_visibility_assistants/openai/secrets/api_key" }

  around { |example| ai_visibility_settings(enabled: true) { example.run } }

  describe "gating" do
    it "is a 404 for a signed in visitor who is not an admin, and keeps the key" do
      create(:dash_ai_assistant, :keyed)
      sign_in create(:user)

      delete path

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::AiVisibility::Assistant.for("openai").api_key).to eq("stored-key")
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "offers Remove beside a stored key and not otherwise" do
      create(:dash_ai_assistant, :keyed)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit"
      link = Nokogiri::HTML5(response.body).at_css("a[aria-label='Remove the stored ChatGPT key']")
      expect(link["href"]).to eq("/telemetry/settings/ai_visibility_assistants/openai/edit?remove=api_key#remove-secret")

      get "/telemetry/settings/ai_visibility_assistants/gemini/edit"
      expect(Nokogiri::HTML5(response.body).at_css("a[aria-label^='Remove the stored']")).to be_nil
    end

    it "asks first, saying the assistant stops being asked" do
      create(:dash_ai_assistant, :keyed)
      create(:dash_ai_prompt)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit", params: { remove: "api_key" }

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("#remove-secret").text)
        .to include("Remove the stored ChatGPT key? ChatGPT stops being asked until a key is saved again.")
      expect(document.at_css("#remove-secret form[action='#{path}'] input[name='_method'][value='delete']")).to be_present
    end

    it "says nothing asks it while there are no prompts" do
      create(:dash_ai_assistant, :keyed)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit", params: { remove: "api_key" }

      expect(response.body).to include("Nothing asks ChatGPT until AI visibility is on and has prompts.")
    end

    it "never offers a key from anywhere else to take over" do
      create(:dash_ai_assistant, :keyed)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit", params: { remove: "api_key" }

      expect(response.body).not_to include("initializer", "used instead")
    end

    it "deletes the key and keeps the row and its models" do
      create(:dash_ai_assistant, :keyed, models: %w[gpt-4.1])

      delete path

      expect(response).to redirect_to("/telemetry/settings/ai_visibility_assistants/openai/edit")
      expect(flash[:notice]).to eq("ChatGPT key removed.")
      assistant = AhoyDashboard::AiVisibility::Assistant.for("openai")
      expect(assistant.read_attribute(:credentials)).to be_nil
      expect(assistant.models).to eq(%w[gpt-4.1])
      expect(AhoyDashboard::AiVisibility.asked_names).not_to include("openai")
    end

    it "reads Nothing stored once the stored key is gone, whatever the environment holds" do
      create(:dash_ai_assistant, :keyed)
      stub_const("ENV", ENV.to_h.merge("OPENAI_API_KEY" => "from-env"))

      delete path
      get "/telemetry/settings/ai_visibility_assistants/openai/edit"

      expect(AhoyDashboard::AiVisibility.api_key("openai")).to be_nil
      expect(response.body).to include("Nothing stored.")
    end

    it "says there was nothing to remove" do
      delete path

      expect(flash[:alert]).to eq("There was no ChatGPT key stored.")
    end

    it "is a 404 for a key the assistant does not take" do
      delete "/telemetry/settings/ai_visibility_assistants/openai/secrets/model"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for an assistant nobody registered" do
      delete "/telemetry/settings/ai_visibility_assistants/copilot/secrets/api_key"

      expect(response).to have_http_status(:not_found)
    end
  end
end
