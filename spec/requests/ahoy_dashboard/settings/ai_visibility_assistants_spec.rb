require "rails_helper"
require "support/ahoy_dashboard/ai_visibility_settings"

RSpec.describe "Dashboard AI visibility assistant settings", type: :request do
  around { |example| ai_visibility_settings(enabled: true) { example.run } }

  describe "gating" do
    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "opens an assistant that has never been set up, on and with its default model picked" do
      get "/telemetry/settings/ai_visibility_assistants/gemini/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Set up Gemini", "Nothing stored.")
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[type=checkbox][name='ai_visibility_assistant[enabled]']")["checked"]).to be_present
      picked = page.css("input[type=checkbox][name='ai_visibility_assistant[models][]'][checked]").map { |box| box["value"] }
      expect(picked).to eq(%w[gemini-2.5-flash])
      offered = page.css("input[type=checkbox][name='ai_visibility_assistant[models][]']").map { |box| box["value"] }
      expect(offered).to eq(AhoyDashboard::AiVisibility.catalog("gemini"))
    end

    it "shows a model that is not in the list in the typed field" do
      create(:dash_ai_assistant, :keyed, models: %w[gpt-5 o3])

      get "/telemetry/settings/ai_visibility_assistants/openai/edit"

      page = Nokogiri::HTML(response.body)
      picked = page.css("input[type=checkbox][name='ai_visibility_assistant[models][]'][checked]").map { |box| box["value"] }
      expect(picked).to eq(%w[gpt-5])
      expect(page.at_css("input[name='ai_visibility_assistant[other_models]']")["value"]).to eq("o3")
    end

    it "is a 404 for an assistant nobody registered" do
      get "/telemetry/settings/ai_visibility_assistants/copilot/edit"

      expect(response).to have_http_status(:not_found)
    end

    it "stores a key encrypted and never prints it back" do
      patch "/telemetry/settings/ai_visibility_assistants/perplexity",
        params: { ai_visibility_assistant: { enabled: "1", models: [ "", "sonar" ], credentials: { api_key: "a-real-key" } } }

      expect(response).to redirect_to("/telemetry/settings/ai_visibility/edit")
      assistant = AhoyDashboard::AiVisibility::Assistant.for("perplexity")
      expect(assistant.api_key).to eq("a-real-key")
      expect(assistant.read_attribute(:credentials)).not_to include("a-real-key")

      get "/telemetry/settings/ai_visibility_assistants/perplexity/edit"
      expect(response.body).not_to include("a-real-key")
      expect(response.body).to include("Stored. Leave this blank to keep it.")
    end

    it "keeps the stored key when the box is left blank and saves the models picked" do
      create(:dash_ai_assistant, :keyed, name: "openai")

      patch "/telemetry/settings/ai_visibility_assistants/openai",
        params: { ai_visibility_assistant: { enabled: "1", models: [ "", "gpt-5", "gpt-4.1" ], other_models: "o3",
                                             credentials: { api_key: "" } } }

      assistant = AhoyDashboard::AiVisibility::Assistant.for("openai")
      expect(assistant.api_key).to eq("stored-key")
      expect(AhoyDashboard::AiVisibility.models_for("openai")).to eq(%w[gpt-5 gpt-4.1 o3])
    end

    it "turns an assistant off so it is not asked" do
      create(:dash_ai_assistant, :keyed, name: "anthropic", models: %w[claude-sonnet-5])

      patch "/telemetry/settings/ai_visibility_assistants/anthropic",
        params: { ai_visibility_assistant: { enabled: "0", models: [ "", "claude-sonnet-5" ], credentials: {} } }

      expect(response).to redirect_to("/telemetry/settings/ai_visibility/edit")
      expect(AhoyDashboard::AiVisibility::Assistant.for("anthropic")).not_to be_enabled
      expect(AhoyDashboard::AiVisibility.asked_names).not_to include("anthropic")
    end

    it "sends back an assistant that is on with no model, pointing at the models" do
      patch "/telemetry/settings/ai_visibility_assistants/gemini",
        params: { ai_visibility_assistant: { enabled: "1", models: [ "" ], other_models: "", credentials: {} } }

      expect(response).to have_http_status(:unprocessable_entity)
      page = Nokogiri::HTML(response.body)
      link = page.at_css(".alert a[href='#ai_visibility_assistant_models']")
      expect(link.text).to include("need at least one, or turn Gemini off")
      expect(page.at_css("fieldset#ai_visibility_assistant_models")).to be_present
      expect(AhoyDashboard::AiVisibility::Assistant.count).to be_zero
    end

    it "says nothing is stored when no key was saved on the screen" do
      get "/telemetry/settings/ai_visibility_assistants/gemini/edit"

      expect(response.body).to include("Nothing stored.")
      expect(response.body).not_to include("initializer")
    end
  end
end
