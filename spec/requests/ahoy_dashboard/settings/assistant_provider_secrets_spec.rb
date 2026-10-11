require "rails_helper"

RSpec.describe "Dashboard assistant key removal", type: :request do
  let(:path) { "/telemetry/settings/assistant_providers/anthropic/secrets/api_key" }

  describe "gating" do
    it "sends a signed out visitor to sign in and keeps the key" do
      create(:dash_assistant_provider, credentials: { api_key: "stored-key" })

      delete path

      expect(response).to redirect_to("/users/sign_in")
      expect(AhoyDashboard::AssistantProvider.for("anthropic").api_key).to eq("stored-key")
    end

    it "is a 404 for a signed in visitor who is not an admin, and keeps the key" do
      create(:dash_assistant_provider, credentials: { api_key: "stored-key" })
      sign_in create(:user)

      delete path

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::AssistantProvider.for("anthropic").api_key).to eq("stored-key")
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "offers Remove beside a stored key" do
      create(:dash_assistant_provider, credentials: { api_key: "stored-key" })

      get "/telemetry/settings/assistant_providers/anthropic/edit"

      link = Nokogiri::HTML5(response.body).at_css("a[aria-label='Remove the stored Anthropic key']")
      expect(link["href"]).to eq("/telemetry/settings/assistant_providers/anthropic/edit?remove=api_key#remove-secret")
    end

    it "offers no Remove when nothing is stored" do
      get "/telemetry/settings/assistant_providers/anthropic/edit"

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("a[aria-label^='Remove the stored']")).to be_nil
      expect(response.body).to include("Nothing stored.")
    end

    it "asks first, naming what stops working when the provider is answering" do
      create(:dash_assistant_provider, :active, credentials: { api_key: "stored-key" })

      get "/telemetry/settings/assistant_providers/anthropic/edit", params: { remove: "api_key" }

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("#remove-secret").text)
        .to include("Remove the stored Anthropic key? The assistant stops answering until a key is saved again.")
      expect(document.at_css("#remove-secret form[action='#{path}'] input[name='_method'][value='delete']")).to be_present
      expect(AhoyDashboard::AssistantProvider.for("anthropic").api_key).to eq("stored-key")
    end

    it "never offers a key from anywhere else to take over" do
      create(:dash_assistant_provider, :active, credentials: { api_key: "stored-key" })

      get "/telemetry/settings/assistant_providers/anthropic/edit", params: { remove: "api_key" }

      expect(response.body).not_to include("initializer", "used instead")
    end

    it "says nothing stops when the provider is not the active one" do
      create(:dash_assistant_provider, credentials: { api_key: "stored-key" })

      get "/telemetry/settings/assistant_providers/anthropic/edit", params: { remove: "api_key" }

      expect(response.body).to include("Nothing uses it while Anthropic is not the active provider.")
    end

    it "does not ask about a key that is not stored" do
      get "/telemetry/settings/assistant_providers/anthropic/edit", params: { remove: "api_key" }

      expect(Nokogiri::HTML5(response.body).at_css("#remove-secret")).to be_nil
    end

    it "deletes the key and keeps the row and its other settings" do
      create(:dash_assistant_provider, :active, model: "claude-opus-4-6", api_base: "https://proxy.example/v1",
                                                credentials: { api_key: "stored-key" })

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
      create(:dash_assistant_provider, :active, credentials: { api_key: "stored-key" })
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "from-env"))

      delete path
      get "/telemetry/settings/assistant_providers/anthropic/edit"

      expect(response.body).to include("Nothing stored.")
      expect(AhoyDashboard::Assistant.api_key).to be_nil
      expect(AhoyDashboard::Assistant.key_source).to eq(:missing)
    end

    it "says there was nothing to remove" do
      delete path

      expect(response).to redirect_to("/telemetry/settings/assistant_providers/anthropic/edit")
      expect(flash[:alert]).to eq("There was no Anthropic key stored.")
      expect(AhoyDashboard::AssistantProvider.count).to be_zero
    end

    it "is a 404 for a key the reader does not have" do
      delete "/telemetry/settings/assistant_providers/anthropic/secrets/model"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a local reader, which takes no key" do
      delete "/telemetry/settings/assistant_providers/lmstudio/secrets/api_key"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a reader nobody registered" do
      delete "/telemetry/settings/assistant_providers/gemini/secrets/api_key"

      expect(response).to have_http_status(:not_found)
    end
  end
end
