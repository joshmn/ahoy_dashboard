require "rails_helper"
require "support/ahoy_dashboard/switches"
require "support/ahoy_dashboard/installation"

RSpec.describe "Dashboard search options", type: :request do
  def page
    Nokogiri::HTML5(response.body)
  end

  def field(id)
    page.at_css("##{id}")
  end

  def settings
    AhoyDashboard::Setting.order(:key).pluck(:key, :value)
  end

  def read(scope, name)
    AhoyDashboard::Preferences.read(scope, name)
  end

  let(:valid) do
    { keywords_provider: "dataforseo", keywords_location: "de", keywords_language: "de",
      backlinks_provider: "serpapi", places_postal_codes: "1",
      places_source: "https://lists.example.com/places_%Y_%m.csv" }
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      patch "/telemetry/settings/search_options", params: { search_options: valid }

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin, and writes nothing" do
      sign_in create(:user)

      expect { patch "/telemetry/settings/search_options", params: { search_options: valid } }.not_to(change { settings })
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "sits on the search provider screen with every field labelled" do
      get "/telemetry/settings/serp_providers"

      form = page.at_css("form[action='/telemetry/settings/search_options']")
      expect(form).to be_present
      %w[search_options_keywords_provider search_options_keywords_location search_options_keywords_language
         search_options_backlinks_provider search_options_places_postal_codes search_options_places_source].each do |id|
        expect(form.at_css("label[for='#{id}']")).to be_present, "expected a label for #{id}"
        expect(field(id)["aria-describedby"]).to include("#{id}_hint")
      end
    end

    it "puts the place list address behind Advanced" do
      get "/telemetry/settings/serp_providers"

      details = field("search_options_places_source").ancestors("details").first
      expect(details).to be_present
      expect(details.at_css("summary").text.squish).to eq("Advanced")
      expect(details["open"]).to be_nil
      expect(page.at_css("#search_options_places_source_hint").text).to include("strftime")
    end

    it "offers every adapter, with blank meaning the rank tracking provider" do
      get "/telemetry/settings/serp_providers"

      %w[search_options_keywords_provider search_options_backlinks_provider].each do |id|
        options = field(id).css("option")
        expect(options.first.text).to eq("Same as rank tracking")
        expect(options.first["value"]).to eq("")
        expect(options.drop(1).map { |option| option["value"] }).to eq(AhoyDashboard::Serp.adapter_names.map(&:to_s))
      end
    end

    it "shows the defaults when nothing is stored" do
      get "/telemetry/settings/serp_providers"

      expect(field("search_options_keywords_provider").at_css("option[selected]")).to be_nil
      expect(field("search_options_keywords_location").at_css("option[selected]")["value"]).to eq("us")
      expect(field("search_options_keywords_language")["value"]).to eq("en")
      expect(field("search_options_places_postal_codes")["checked"]).to be_nil
      expect(field("search_options_places_source")["value"]).to eq(AhoyDashboard::Preferences::PLACES_SOURCE)
    end

    it "shows what is stored" do
      ahoy_dashboard_preferences(:keywords, provider: :searchapi, location: "fr", language: "fr")
      ahoy_dashboard_preferences(:backlinks, provider: :dataforseo)
      ahoy_dashboard_preferences(:places, postal_codes: true)

      get "/telemetry/settings/serp_providers"

      expect(field("search_options_keywords_provider").at_css("option[selected]")["value"]).to eq("searchapi")
      expect(field("search_options_keywords_location").at_css("option[selected]")["value"]).to eq("fr")
      expect(field("search_options_keywords_language")["value"]).to eq("fr")
      expect(field("search_options_backlinks_provider").at_css("option[selected]")["value"]).to eq("dataforseo")
      expect(field("search_options_places_postal_codes")["checked"]).to eq("checked")
    end

    it "saves every field and the readers use them from then on" do
      patch "/telemetry/settings/search_options", params: { search_options: valid }

      expect(response).to redirect_to("/telemetry/settings/serp_providers#search-options")
      expect(AhoyDashboard::Keywords.provider).to eq(:dataforseo)
      expect(AhoyDashboard::Keywords.location).to eq("de")
      expect(AhoyDashboard::Keywords.language).to eq("de")
      expect(AhoyDashboard::Backlinks.provider).to eq(:serpapi)
      expect(AhoyDashboard::Places.postal_codes?).to be(true)
      expect(AhoyDashboard::Places.source_url(Date.new(2026, 3, 1))).to eq("https://lists.example.com/places_2026_03.csv")
    end

    it "goes back to the defaults when the fields are cleared" do
      ahoy_dashboard_preferences(:keywords, provider: :searchapi, language: "fr")
      ahoy_dashboard_preferences(:backlinks, provider: :dataforseo)
      ahoy_dashboard_preferences(:places, postal_codes: true, source: "https://lists.example.com/%Y.csv")

      patch "/telemetry/settings/search_options",
            params: { search_options: { keywords_provider: "", keywords_location: "us", keywords_language: "",
                                        backlinks_provider: "", places_postal_codes: "0", places_source: "" } }

      expect(response).to redirect_to("/telemetry/settings/serp_providers#search-options")
      expect(AhoyDashboard::Keywords.provider).to eq(AhoyDashboard::Serp.provider)
      expect(AhoyDashboard::Backlinks.provider).to eq(AhoyDashboard::Serp.provider)
      expect(read(:keywords, :language)).to eq("en")
      expect(read(:places, :postal_codes)).to be(false)
      expect(read(:places, :source)).to eq(AhoyDashboard::Preferences::PLACES_SOURCE)
      %i[provider language].each { |name| expect(AhoyDashboard::Preferences.stored?(:keywords, name)).to be(false) }
      expect(AhoyDashboard::Preferences.stored?(:places, :source)).to be(false)
    end

    describe "refusing" do
      def refused(**changes)
        expect { patch "/telemetry/settings/search_options", params: { search_options: valid.merge(changes) } }
          .not_to(change { settings })

        expect(response).to have_http_status(:unprocessable_entity)
        page.at_css("[role='alert']").text.squish
      end

      it "names a provider it does not know" do
        expect(refused(keywords_provider: "bing")).to include("Keyword research provider", %("bing" is not a search provider))
        expect(refused(backlinks_provider: "ahrefs")).to include("Backlinks provider", %("ahrefs" is not a search provider))
      end

      it "names a country it does not know" do
        expect(refused(keywords_location: "zz")).to include("Search from", %("zz" is not a country))
      end

      it "names a language that is not a code" do
        expect(refused(keywords_language: "english please")).to include("Language", %("english please" is not a language code))
        expect(field("search_options_keywords_language")["aria-invalid"]).to eq("true")
      end

      it "refuses a list address that is not a web address, and opens Advanced to show it" do
        expect(refused(places_source: "ftp://lists.example.com/%Y.csv")).to include("Monthly list address has to be a web address")
        expect(field("search_options_places_source").ancestors("details").first["open"]).to be_present
      end

      it "still renders the provider table" do
        refused(keywords_language: "nope nope")

        expect(page.css("tbody tr").size).to eq(AhoyDashboard::SerpProvider::NAMES.size)
      end
    end

    describe "when a feature is not ready" do
      it "says nothing when keyword research, backlinks and places are all on" do
        switch_on_ahoy_dashboard(:keywords, :backlinks, :places)

        get "/telemetry/settings/serp_providers"

        %w[keywords backlinks places].each { |name| expect(page.at_css("##{name}-state")).to be_nil }
      end

      it "keeps every group and says which are switched off" do
        switch_off_ahoy_dashboard(:keywords, :backlinks, :places)

        get "/telemetry/settings/serp_providers"

        %w[keywords backlinks places].each do |name|
          line = page.at_css("##{name}-state")
          expect(line.text.squish).to include("Switched off")
          expect(line.at_css("a")["href"]).to eq("/telemetry/settings/features#feature-#{name}")
        end
        expect(field("search_options_places_postal_codes")).to be_present
      end

      it "says when the place list is not installed and still saves its options" do
        uninstall_ahoy_dashboard(:places)

        get "/telemetry/settings/serp_providers"

        expect(page.at_css("#places-state").text.squish).to include("Not installed in this app yet")

        patch "/telemetry/settings/search_options", params: { search_options: valid }

        expect(read(:places, :postal_codes)).to be(true)
      end
    end
  end
end
