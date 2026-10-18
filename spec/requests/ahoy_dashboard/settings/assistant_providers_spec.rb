require "rails_helper"

RSpec.describe "Dashboard assistant settings", type: :request do
  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "lists every reader and which one is answering" do
      allow(AhoyDashboard::Assistant).to receive(:available?).and_return(true)

      get "/telemetry/settings/assistant_providers"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Anthropic", "OpenAI", "DeepSeek", "OpenAI-compatible", "Active")
      expect(response.body).not_to include("LM Studio (local)")
    end

    it "calls the chosen reader selected rather than active while the assistant is off" do
      allow(AhoyDashboard::Assistant).to receive(:available?).and_return(false)

      get "/telemetry/settings/assistant_providers"

      badges = document.css(".badge").map { |badge| badge.text.strip }
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

    it "takes a key for an OpenAI-compatible server without needing one" do
      get "/telemetry/settings/assistant_providers/compatible/edit"

      page = document
      expect(page.at_css("#assistant_provider_credentials_api_key")).to be_present
      expect(page.at_css("label[for='assistant_provider_credentials_api_key']").text).to include("(optional)")
      expect(response.body).to include("Nothing leaves the machine")
      expect(row_key_after_index("compatible")).to eq("Not needed")
    end

    it "requires a DeepSeek key and says how long an answer can run" do
      get "/telemetry/settings/assistant_providers/deepseek/edit"

      page = document
      expect(page.at_css("label[for='assistant_provider_credentials_api_key']").text).not_to include("(optional)")
      expect(page.at_css("#assistant_provider_max_tokens")["placeholder"]).to eq("65536")
      expect(response.body).to include("Leave it blank for 65,536.", "deepseek-flash")
      expect(page.at_css("#assistant_provider_api_base")["placeholder"]).to eq("https://api.deepseek.com")
      expect(response.body).not_to include("Usually ends in")
    end

    it "says a stored key for an OpenAI-compatible server is stored" do
      create(:dash_assistant_provider, name: "compatible", model: "some/model", api_base: "https://openrouter.ai/api/v1",
                                        credentials: { api_key: "sk-or" })

      expect(row_key_after_index("compatible")).to eq("Stored here")
    end

    def row_key_after_index(name)
      get "/telemetry/settings/assistant_providers"
      row(name)[2]
    end

    def row(name)
      document.at_css("#assistant-provider-#{name}").css("td").map { |cell| cell.text.squish }
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

    it "does not promise an OpenAI-compatible server is on the machine once its endpoint points elsewhere" do
      create(:dash_assistant_provider, name: "compatible", model: "qwen", api_base: "https://gpu.example.net/v1")

      get "/telemetry/settings/assistant_providers/compatible/edit"

      expect(response.body).not_to include("Nothing leaves the machine")
      expect(response.body).to include("go to gpu.example.net", "A key is optional")
    end

    it "still says an OpenAI-compatible server stays on the machine on a loopback endpoint" do
      create(:dash_assistant_provider, name: "compatible", model: "qwen", api_base: "http://127.0.0.1:1234/v1")

      get "/telemetry/settings/assistant_providers/compatible/edit"

      expect(response.body).to include("Nothing leaves the machine")
    end

    describe "an install whose stored reader is lmstudio" do
      let!(:legacy) do
        create(:dash_assistant_provider, :active, name: "lmstudio", model: "qwen", temperature: 0.4)
      end

      it "shows that row as the OpenAI-compatible reader, in use" do
        allow(AhoyDashboard::Assistant).to receive(:available?).and_return(true)

        get "/telemetry/settings/assistant_providers"

        compatible = row("compatible")
        expect(compatible[0]).to include("OpenAI-compatible", "Active")
        expect(compatible[1]).to include("qwen", "Temperature 0.4")
        expect(compatible[2]).to eq("Not needed")
        expect(document.at_css("#assistant-provider-lmstudio")).to be_nil
      end

      it "opens the old address on the OpenAI-compatible form with what was saved" do
        get "/telemetry/settings/assistant_providers/lmstudio/edit"

        page = document
        expect(page.at_css("#assistant_provider_model")["value"]).to eq("qwen")
        expect(page.at_css("#assistant_provider_api_base")["placeholder"]).to eq("http://localhost:1234/v1")
        expect(page.at_css("form[action='/telemetry/settings/assistant_providers/compatible']")).to be_present
      end

      it "moves the row onto the new name the first time it is saved, keeping what it had" do
        patch "/telemetry/settings/assistant_providers/compatible",
          params: { assistant_provider: { model: "qwen3", api_base: "", temperature: "0.4", active: "1",
                                          credentials: { api_key: "sk-local" } } }

        expect(response).to redirect_to("/telemetry/settings/assistant_providers")
        expect(AhoyDashboard::AssistantProvider.pluck(:id, :name)).to eq([ [ legacy.id, "compatible" ] ])
        expect(legacy.reload).to be_active
        expect(legacy.model).to eq("qwen3")
        expect(legacy.api_key).to eq("sk-local")
        expect(AhoyDashboard::Assistant.reader).to eq("compatible")
      end
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

    it "refuses an OpenAI-compatible reader with no model named, because there is no default to fall back on" do
      patch "/telemetry/settings/assistant_providers/compatible",
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

      page = document
      input = page.at_css("#assistant_provider_model")
      options = page.css("datalist##{input["list"]} option").map { |option| option["value"] }
      expect(options).to include("claude-opus-5", "claude-sonnet-4-6")
      expect(input["type"]).to eq("text")
    end

    it "draws the page with the built in list and asks the provider for its own afterwards" do
      create(:dash_assistant_provider, name: "deepseek", credentials: { api_key: "sk-deep" })

      get "/telemetry/settings/assistant_providers/deepseek/edit"

      page = document
      frame = page.at_css("tm-frame#assistant_provider_models")
      expect(frame["src"]).to eq("/telemetry/settings/assistant_providers/deepseek/models")
      expect(frame.css("datalist#assistant_provider_model_options option").map { |option| option["value"] })
        .to eq(%w[deepseek-flash deepseek-v4-pro])
      expect(page.at_css("#assistant_provider_model")["list"]).to eq("assistant_provider_model_options")
      expect(WebMock).not_to have_requested(:any, /api\.deepseek\.com/)
    end

    it "starts an OpenAI-compatible reader with an empty list for its server to fill" do
      get "/telemetry/settings/assistant_providers/compatible/edit"

      frame = document.at_css("tm-frame#assistant_provider_models")
      expect(frame["src"]).to eq("/telemetry/settings/assistant_providers/compatible/models")
      expect(frame.css("datalist option")).to be_empty
    end
  end

  describe "the provider's own model list" do
    before { sign_in create(:user, :admin) }

    def frame_get(path)
      get_frame(path, "assistant_provider_models")
    end

    it "fills the frame with the models the provider lists" do
      create(:dash_assistant_provider, name: "deepseek", credentials: { api_key: "sk-deep" })
      stub_request(:get, "https://api.deepseek.com/models").to_return(
        status: 200, body: JSON.generate(object: "list", data: [ { id: "deepseek-flash", name: "DeepSeek-V4.1-Flash" },
                                                                 { id: "deepseek-v5-preview" } ])
      )

      frame_get "/telemetry/settings/assistant_providers/deepseek/models"

      expect(response).to have_http_status(:ok)
      options = document.css("tm-frame#assistant_provider_models datalist#assistant_provider_model_options option")
      expect(options.map { |option| [ option["value"], option["label"] ] })
        .to eq([ [ "deepseek-flash", "DeepSeek-V4.1-Flash" ], [ "deepseek-v5-preview", nil ] ])
      expect(response.body).not_to include("<html")
    end

    it "fills it with the built in list when the provider cannot be asked" do
      create(:dash_assistant_provider, name: "deepseek", credentials: { api_key: "sk-deep" })
      stub_request(:get, "https://api.deepseek.com/models").to_return(status: 503, body: "")

      frame_get "/telemetry/settings/assistant_providers/deepseek/models"

      expect(response).to have_http_status(:ok)
      expect(document.css("datalist option").map { |option| option["value"] })
        .to eq(%w[deepseek-flash deepseek-v4-pro])
    end

    it "sends a request that is not the frame's back to the form" do
      get "/telemetry/settings/assistant_providers/deepseek/models"

      expect(response).to redirect_to("/telemetry/settings/assistant_providers/deepseek/edit")
    end

    it "is a 404 for a reader nobody registered" do
      frame_get "/telemetry/settings/assistant_providers/gemini/models"

      expect(response).to have_http_status(:not_found)
    end
  end
end
