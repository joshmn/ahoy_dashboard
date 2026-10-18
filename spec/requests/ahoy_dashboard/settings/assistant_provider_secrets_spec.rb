require "rails_helper"

RSpec.describe "Dashboard assistant key removal", type: :request do
  def store_secret
    create(:dash_assistant_provider, :active, :keyed)
  end

  let(:path) { "/telemetry/settings/assistant_providers/anthropic/secrets/api_key" }

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    include_examples "a stored secret removal",
                     secret_path: "/telemetry/settings/assistant_providers/anthropic/secrets/api_key",
                     confirm_path: "/telemetry/settings/assistant_providers/anthropic/edit?remove=api_key",
                     edit_path: "/telemetry/settings/assistant_providers/anthropic/edit",
                     word: "key", nothing: "There was no Anthropic key stored.", model: AhoyDashboard::AssistantProvider,
                     unknown: {
                       "a key the reader does not have" => "/telemetry/settings/assistant_providers/anthropic/secrets/model",
                       "a reader nobody registered" => "/telemetry/settings/assistant_providers/gemini/secrets/api_key"
                     }


    it "offers Remove beside a stored key" do
      create(:dash_assistant_provider, :keyed)

      get "/telemetry/settings/assistant_providers/anthropic/edit"

      link = document.at_css("a[aria-label='Remove the stored Anthropic key']")
      expect(link["href"]).to eq("/telemetry/settings/assistant_providers/anthropic/edit?remove=api_key#remove-secret")
    end

    it "offers no Remove when nothing is stored" do
      get "/telemetry/settings/assistant_providers/anthropic/edit"

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("a[aria-label^='Remove the stored']")).to be_nil
      expect(response.body).to include("Nothing stored.")
    end

    it "asks first, naming what stops working when the provider is answering" do
      create(:dash_assistant_provider, :active, :keyed)

      get "/telemetry/settings/assistant_providers/anthropic/edit", params: { remove: "api_key" }

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("#remove-secret").text)
        .to include("Remove the stored Anthropic key? The assistant stops answering until a key is saved again.")
      expect(document.at_css("#remove-secret form[action='#{path}'] input[name='_method'][value='delete']")).to be_present
      expect(AhoyDashboard::AssistantProvider.for("anthropic").api_key).to eq("stored-key")
    end

    it "says nothing stops when the provider is not the active one" do
      create(:dash_assistant_provider, :keyed)

      get "/telemetry/settings/assistant_providers/anthropic/edit", params: { remove: "api_key" }

      expect(response.body).to include("Nothing uses it while Anthropic is not the active provider.")
    end

    it "does not ask about a key that is not stored" do
      get "/telemetry/settings/assistant_providers/anthropic/edit", params: { remove: "api_key" }

      expect(document.at_css("#remove-secret")).to be_nil
    end

    it "deletes the key and keeps the row and its other settings" do
      create(:dash_assistant_provider, :active, :keyed, model: "claude-opus-4-6", api_base: "https://proxy.example/v1")

      delete path

      expect(response).to redirect_to("/telemetry/settings/assistant_providers/anthropic/edit")
      expect(flash[:notice]).to eq("Anthropic key removed.")
      provider = AhoyDashboard::AssistantProvider.for("anthropic")
      expect(provider.api_key).to be_nil
      expect(provider.read_attribute(:credentials)).to be_nil
      expect(provider).to be_active
      expect(provider.model).to eq("claude-opus-4-6")
      expect(provider.api_base).to eq("https://proxy.example/v1")
    end

    it "reads Nothing stored once the stored key is gone, whatever the environment holds" do
      create(:dash_assistant_provider, :active, :keyed)
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "from-env"))

      delete path
      get "/telemetry/settings/assistant_providers/anthropic/edit"

      expect(response.body).to include("Nothing stored.")
      expect(AhoyDashboard::Assistant.api_key).to be_nil
      expect(AhoyDashboard::Assistant.key_source).to eq(:missing)
    end

    it "removes a key saved for an OpenAI-compatible server, and says it asks without one from then on" do
      create(:dash_assistant_provider, :active, name: "compatible", model: "some/model",
                                                 api_base: "https://openrouter.ai/api/v1", credentials: { api_key: "sk-or" })

      get "/telemetry/settings/assistant_providers/compatible/edit", params: { remove: "api_key" }

      expect(document.at_css("#remove-secret").text)
        .to include("The assistant asks without a key from then on, which only works if the server needs none.")

      delete "/telemetry/settings/assistant_providers/compatible/secrets/api_key"

      expect(response).to redirect_to("/telemetry/settings/assistant_providers/compatible/edit")
      expect(AhoyDashboard::AssistantProvider.for("compatible").api_key).to be_nil
    end

    it "removes a key from a row an install saved under lmstudio" do
      create(:dash_assistant_provider, name: "lmstudio", model: "qwen", credentials: { api_key: "sk-local" })

      delete "/telemetry/settings/assistant_providers/lmstudio/secrets/api_key"

      expect(response).to redirect_to("/telemetry/settings/assistant_providers/compatible/edit")
      expect(AhoyDashboard::AssistantProvider.for("compatible").api_key).to be_nil
    end
  end
end
