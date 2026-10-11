require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe "Dashboard serp provider settings", type: :request do
  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/serp_providers"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/serp_providers/serpapi/edit"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "lists every adapter and which one is running" do
      get "/telemetry/settings/serp_providers"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SerpApi", "Sample data", "Active")
    end

    describe "the credentials column" do
      def credentials_for(label)
        row = Nokogiri::HTML5(response.body).css("tbody tr").find { |node| node.at_css("td")&.text&.include?(label) }
        row.css("td")[1].text.squish
      end

      it "says a provider with nothing saved on the screen is missing its key" do
        get "/telemetry/settings/serp_providers"

        expect(credentials_for("SerpApi")).to eq("Missing")
        expect(credentials_for("SearchApi")).to eq("Missing")
      end

      it "says a key saved on the screen is stored" do
        create(:dash_serp_provider, :serpapi)

        get "/telemetry/settings/serp_providers"

        expect(credentials_for("SerpApi")).to eq("Stored")
      end

      it "says a provider with only half its keys saved is missing them" do
        create(:dash_serp_provider, name: "dataforseo", credentials: { login: "stored-login" })

        get "/telemetry/settings/serp_providers"

        expect(credentials_for("DataForSEO")).to eq("Missing")
      end

      it "says sample data needs nothing" do
        get "/telemetry/settings/serp_providers"

        expect(credentials_for("Sample data")).to eq("None needed")
      end

      it "uses the loaded provider records for every credentials cell" do
        create(:dash_serp_provider, name: "dataforseo", credentials: { login: "stored-login", password: "stored-password" })
        queries = []
        subscriber = ->(_name, _started, _finished, _id, payload) do
          sql = payload[:sql]
          queries << sql if sql.include?('FROM "ahoy_dashboard_serp_providers"')
        end

        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          get "/telemetry/settings/serp_providers"
        end

        expect(credentials_for("DataForSEO")).to eq("Stored")
        expect(queries.size).to eq(2) # The provider list and the current-provider lookup.
        expect(response.body).not_to include("stored-login", "stored-password")
      end
    end

    it "is a 404 for a name nobody registered" do
      get "/telemetry/settings/serp_providers/google/edit"

      expect(response).to have_http_status(:not_found)
    end

    it "opens a provider that has never been set up" do
      get "/telemetry/settings/serp_providers/serpapi/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("API key", "Nothing stored.")
    end

    it "says a key is stored without ever printing it back" do
      create(:dash_serp_provider, :serpapi)

      get "/telemetry/settings/serp_providers/serpapi/edit"

      expect(response.body).to include("Leave this blank to keep it")
      expect(response.body).not_to include("stored-key")
    end

    it "stores a key encrypted" do
      patch "/telemetry/settings/serp_providers/serpapi",
        params: { serp_provider: { monthly_cap_units: "1000", active: "0",
                                   credentials: { api_key: "a-real-key" } } }

      expect(response).to redirect_to("/telemetry/settings/serp_providers")
      provider = AhoyDashboard::SerpProvider.for("serpapi")
      expect(provider.credential(:api_key)).to eq("a-real-key")
      expect(provider.read_attribute(:credentials)).not_to include("a-real-key")
    end

    it "keeps the key that is already there when the box is left blank" do
      create(:dash_serp_provider, :serpapi, monthly_cap_units: 10)

      patch "/telemetry/settings/serp_providers/serpapi",
        params: { serp_provider: { monthly_cap_units: "20", active: "0",
                                   credentials: { api_key: "" } } }

      provider = AhoyDashboard::SerpProvider.for("serpapi")
      expect(provider.credential(:api_key)).to eq("stored-key")
      expect(provider.monthly_cap_units).to eq(20)
    end

    it "switches every other provider off when one is turned on" do
      create(:dash_serp_provider, :active)

      patch "/telemetry/settings/serp_providers/serpapi",
        params: { serp_provider: { monthly_cap_units: "500", active: "1",
                                   credentials: { api_key: "a-real-key" } } }

      expect(AhoyDashboard::SerpProvider.for("fake")).not_to be_active
      expect(AhoyDashboard::SerpProvider.for("serpapi")).to be_active
      expect(AhoyDashboard::Serp.provider).to eq(:serpapi)
    end

    it "refuses a ceiling that is not a whole number of searches" do
      patch "/telemetry/settings/serp_providers/serpapi",
        params: { serp_provider: { monthly_cap_units: "-4", active: "0", credentials: {} } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::SerpProvider.count).to be_zero
    end

    it "takes no credentials for an adapter that needs none" do
      patch "/telemetry/settings/serp_providers/fake",
        params: { serp_provider: { monthly_cap_units: "0", active: "1" } }

      expect(response).to redirect_to("/telemetry/settings/serp_providers")
      expect(AhoyDashboard::SerpProvider.for("fake")).to be_active
    end
  end
end
