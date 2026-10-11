require "rails_helper"
require "support/ahoy_dashboard/assistant"

RSpec.describe "Dashboard assistant settings", type: :request do
  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/assistant_providers"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/assistant_providers/anthropic/edit"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "lists every reader and which one is answering" do
      allow(AhoyDashboard::Assistant).to receive(:available?).and_return(true)

      get "/telemetry/settings/assistant_providers"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Anthropic", "OpenAI", "LM Studio", "Active")
    end

    it "calls the chosen reader selected rather than active while the assistant is off" do
      allow(AhoyDashboard::Assistant).to receive(:available?).and_return(false)

      get "/telemetry/settings/assistant_providers"

      badges = Nokogiri::HTML5(response.body).css(".badge").map { |badge| badge.text.strip }
      expect(badges).to include("Selected")
      expect(badges).not_to include("Active")
    end

    it "says a key is missing when nothing is stored here, whatever the environment holds" do
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "from-env", "OPENAI_API_KEY" => "from-env"))

      get "/telemetry/settings/assistant_providers"

      expect(row("anthropic")[2]).to eq("Missing")
      expect(row("openai")[2]).to eq("Missing")
      expect(response.body).not_to include("From credentials")
    end

    it "says a local reader needs no key at all" do
      get "/telemetry/settings/assistant_providers/lmstudio/edit"

      expect(response.body).not_to include("assistant_provider_credentials_api_key")
      expect(response.body).to include("Nothing leaves the machine")
    end

    def row(name)
      Nokogiri::HTML5(response.body).at_css("#assistant-provider-#{name}").css("td").map { |cell| cell.text.squish }
    end

    it "shows the last error a provider sent back, and when" do
      create(:dash_assistant_provider, :active, last_error: "401 from the model: invalid x-api-key",
                                                 last_error_at: 2.hours.ago)

      get "/telemetry/settings/assistant_providers"

      expect(row("anthropic")[3]).to include("401 from the model: invalid x-api-key", "2 hours ago")
      expect(row("openai")[3]).to eq("None")
    end

    it "does not pass a provider saved without Use this one off as the one in use" do
      create(:dash_assistant_provider, name: "anthropic", model: "claude-opus-4-6",
                                        credentials: { api_key: "saved-but-unused" })

      get "/telemetry/settings/assistant_providers"

      anthropic = row("anthropic")
      expect(anthropic[0]).to include("Saved without Use this one, so the settings saved here are not used.")
      expect(anthropic[1]).to eq(AhoyDashboard::Assistant.model_name)
      expect(anthropic[1]).not_to eq("claude-opus-4-6")
      expect(anthropic[2]).to eq("Missing")
    end

    it "shows a provider marked Use this one with its own key and model" do
      create(:dash_assistant_provider, :active, name: "anthropic", model: "claude-opus-4-6",
                                                 credentials: { api_key: "in-use" })

      get "/telemetry/settings/assistant_providers"

      anthropic = row("anthropic")
      expect(anthropic[0]).not_to include("Saved without")
      expect(anthropic[1]).to eq("claude-opus-4-6")
      expect(anthropic[2]).to eq("Stored here")
    end

    it "shows each reader's default model when no provider is marked Use this one" do
      get "/telemetry/settings/assistant_providers"

      expect(row("anthropic")[1]).to eq("claude-sonnet-4-6")
      expect(row("openai")[1]).to eq("gpt-4.1")
    end

    it "does not promise LM Studio stays on the machine once its endpoint points elsewhere" do
      create(:dash_assistant_provider, name: "lmstudio", model: "qwen", api_base: "https://gpu.example.net/v1")

      get "/telemetry/settings/assistant_providers/lmstudio/edit"

      expect(response.body).not_to include("Nothing leaves the machine")
      expect(response.body).to include("go to gpu.example.net")
    end

    it "still says LM Studio stays on the machine on a loopback endpoint" do
      create(:dash_assistant_provider, name: "lmstudio", model: "qwen", api_base: "http://127.0.0.1:1234/v1")

      get "/telemetry/settings/assistant_providers/lmstudio/edit"

      expect(response.body).to include("Nothing leaves the machine")
    end

    it "is a 404 for a reader nobody registered" do
      get "/telemetry/settings/assistant_providers/gemini/edit"

      expect(response).to have_http_status(:not_found)
    end

    it "stores a key encrypted and never prints it back" do
      patch "/telemetry/settings/assistant_providers/anthropic",
        params: { assistant_provider: { model: "", api_base: "", active: "1",
                                        credentials: { api_key: "a-real-key" } } }

      expect(response).to redirect_to("/telemetry/settings/assistant_providers")
      provider = AhoyDashboard::AssistantProvider.for("anthropic")
      expect(provider.api_key).to eq("a-real-key")
      expect(provider.read_attribute(:credentials)).not_to include("a-real-key")

      get "/telemetry/settings/assistant_providers/anthropic/edit"
      expect(response.body).not_to include("a-real-key")
    end

    it "keeps the stored key when the box is left blank" do
      create(:dash_assistant_provider, credentials: { api_key: "already-here" })

      patch "/telemetry/settings/assistant_providers/anthropic",
        params: { assistant_provider: { model: "claude-opus-4-6", api_base: "", active: "0",
                                        credentials: { api_key: "" } } }

      provider = AhoyDashboard::AssistantProvider.for("anthropic")
      expect(provider.api_key).to eq("already-here")
      expect(provider.model).to eq("claude-opus-4-6")
    end

    it "switches every other reader off when one is turned on" do
      create(:dash_assistant_provider, :active, name: "openai")

      patch "/telemetry/settings/assistant_providers/anthropic",
        params: { assistant_provider: { model: "", api_base: "", active: "1", credentials: {} } }

      expect(AhoyDashboard::AssistantProvider.for("openai")).not_to be_active
      expect(AhoyDashboard::Assistant.reader).to eq("anthropic")
    end

    it "refuses a local reader with no model named, because there is no default to fall back on" do
      patch "/telemetry/settings/assistant_providers/lmstudio",
        params: { assistant_provider: { model: "", api_base: "", active: "1", credentials: {} } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("has to be named")
      expect(AhoyDashboard::AssistantProvider.count).to be_zero
    end

    it "saves a temperature and an output limit and the assistant sends them" do
      patch "/telemetry/settings/assistant_providers/openai",
        params: { assistant_provider: { model: "gpt-4.1", api_base: "", temperature: "0.3", max_tokens: "2000",
                                        active: "1", credentials: { api_key: "k" } } }

      expect(response).to redirect_to("/telemetry/settings/assistant_providers")
      expect(AhoyDashboard::Assistant.temperature).to eq(0.3)
      expect(AhoyDashboard::Assistant.max_tokens).to eq(2_000)

      get "/telemetry/settings/assistant_providers"
      expect(row("openai")[1]).to include("Temperature 0.3, up to 2,000 tokens")
    end

    it "clears the temperature and the output limit when the boxes are emptied" do
      create(:dash_assistant_provider, :active, temperature: 0.5, max_tokens: 1_000)

      patch "/telemetry/settings/assistant_providers/anthropic",
        params: { assistant_provider: { model: "", api_base: "", temperature: "", max_tokens: "", active: "1",
                                        credentials: {} } }

      provider = AhoyDashboard::AssistantProvider.for("anthropic")
      expect(provider.temperature).to be_nil
      expect(provider.max_tokens).to be_nil
    end

    it "refuses a temperature out of range and an output limit that is not a whole number" do
      patch "/telemetry/settings/assistant_providers/anthropic",
        params: { assistant_provider: { model: "", api_base: "", temperature: "3", max_tokens: "0", active: "1",
                                        credentials: {} } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("has to be between 0 and 2", "has to be a whole number from 1 to")
      expect(AhoyDashboard::AssistantProvider.count).to be_zero
    end

    it "offers the reader's known models without limiting the box to them" do
      get "/telemetry/settings/assistant_providers/anthropic/edit"

      page = Nokogiri::HTML5(response.body)
      input = page.at_css("#assistant_provider_model")
      options = page.css("datalist##{input["list"]} option").map { |option| option["value"] }
      expect(options).to include("claude-opus-5", "claude-sonnet-4-6")
      expect(input["type"]).to eq("text")
    end

    it "offers no model list for a local reader, which names whatever it has loaded" do
      get "/telemetry/settings/assistant_providers/lmstudio/edit"

      expect(Nokogiri::HTML5(response.body).at_css("#assistant_provider_model")["list"]).to be_nil
    end
  end
end
