require "rails_helper"

RSpec.describe "Dashboard search provider credential removal", type: :request do
  def store_secret
    create(:dash_serp_provider, :serpapi, :active)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    include_examples "a stored secret removal",
                     secret_path: "/telemetry/settings/serp_providers/serpapi/secrets/api_key",
                     confirm_path: "/telemetry/settings/serp_providers/serpapi/edit?remove=api_key",
                     edit_path: "/telemetry/settings/serp_providers/serpapi/edit",
                     word: "key", nothing: "There was no SerpApi API key stored.", model: AhoyDashboard::SerpProvider,
                     unknown: { "a provider nobody registered" => "/telemetry/settings/serp_providers/google/secrets/api_key" }


    it "offers Remove beside each stored credential and only those" do
      create(:dash_serp_provider, name: "dataforseo", credentials: { login: "me@example.com" })

      get "/telemetry/settings/serp_providers/dataforseo/edit"

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("a[aria-label='Remove the stored DataForSEO login']")["href"])
        .to eq("/telemetry/settings/serp_providers/dataforseo/edit?remove=login#remove-secret")
      expect(document.at_css("a[aria-label='Remove the stored DataForSEO password']")).to be_nil
    end

    it "posts each credential under credentials, as a password box that never shows what is stored" do
      create(:dash_serp_provider, name: "dataforseo", credentials: { login: "me@example.com" })

      get "/telemetry/settings/serp_providers/dataforseo/edit"

      document = Nokogiri::HTML5(response.body)
      login = document.at_css("input#serp_provider_credentials_login")
      expect(login.attributes.slice("type", "name", "autocomplete").transform_values(&:value))
        .to eq("type" => "password", "name" => "serp_provider[credentials][login]", "autocomplete" => "off")
      expect(login["value"]).to be_nil
      expect(document.at_css("label[for='serp_provider_credentials_login']")).to be_present
      expect(document.at_css("#serp_provider_login_hint").text).to eq(AhoyDashboard::Settings::StoredSecretPresenter::STORED_HINT)
      expect(document.at_css("#serp_provider_password_hint").text).to eq(AhoyDashboard::Settings::StoredSecretPresenter::MISSING_HINT)
    end

    it "asks first, naming everything that runs through the active provider" do
      create(:dash_serp_provider, :serpapi, :active)
      allow(AhoyDashboard::Keywords).to receive_messages(enabled?: true, provider: :serpapi)
      allow(AhoyDashboard::Backlinks).to receive_messages(enabled?: false)

      get "/telemetry/settings/serp_providers/serpapi/edit", params: { remove: "api_key" }

      expect(document.at_css("#remove-secret").text)
        .to include("Remove the stored SerpApi API key? Rank checks and keyword research stop until it is saved again.")
    end

    it "names keyword research on a provider that is not the active one but still runs it" do
      create(:dash_serp_provider, :active)
      create(:dash_serp_provider, name: "dataforseo", credentials: { login: "me@example.com", password: "hunter2" })
      allow(AhoyDashboard::Keywords).to receive_messages(enabled?: true, provider: :dataforseo)
      allow(AhoyDashboard::Backlinks).to receive_messages(enabled?: false)

      get "/telemetry/settings/serp_providers/dataforseo/edit", params: { remove: "password" }

      expect(document.at_css("#remove-secret").text)
        .to include("Remove the stored DataForSEO password? Keyword research stops until it is saved again.")
    end

    it "says nothing stops when the provider is not the active one" do
      create(:dash_serp_provider, :serpapi)

      get "/telemetry/settings/serp_providers/serpapi/edit", params: { remove: "api_key" }

      expect(response.body).to include("Nothing uses it while SerpApi is not the active provider.")
    end

    it "deletes one credential and keeps the others and the row" do
      create(:dash_serp_provider, :active, name: "dataforseo", monthly_cap_units: 900,
                                           credentials: { login: "me@example.com", password: "hunter2" })

      delete "/telemetry/settings/serp_providers/dataforseo/secrets/password"

      expect(response).to redirect_to("/telemetry/settings/serp_providers/dataforseo/edit")
      expect(flash[:notice]).to eq("DataForSEO password removed.")
      provider = AhoyDashboard::SerpProvider.for("dataforseo")
      expect(provider.credentials).to eq(login: "me@example.com")
      expect(provider.monthly_cap_units).to eq(900)
      expect(provider).to be_active
    end

    it "reads Nothing stored once the last credential is gone" do
      create(:dash_serp_provider, :serpapi)

      delete "/telemetry/settings/serp_providers/serpapi/secrets/api_key"
      get "/telemetry/settings/serp_providers/serpapi/edit"

      expect(AhoyDashboard::SerpProvider.for("serpapi").read_attribute(:credentials)).to be_nil
      expect(response.body).to include("Nothing stored.")
    end

    it "is a 404 for a key the adapter does not take" do
      create(:dash_serp_provider, :serpapi)

      delete "/telemetry/settings/serp_providers/serpapi/secrets/password"

      expect(response).to have_http_status(:not_found)
    end
  end
end
