require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe "Dashboard Search Console redirect URL", type: :request do
  def page
    Nokogiri::HTML5(response.body)
  end

  def field
    page.at_css("#search_console_redirect_redirect_uri")
  end

  def settings
    AhoyDashboard::Setting.order(:key).pluck(:key, :value)
  end

  let(:override) { "https://dash.example.com:8443/telemetry/settings/google_callback" }

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      patch "/telemetry/settings/search_console_redirect", params: { search_console_redirect: { redirect_uri: override } }

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin, and writes nothing" do
      sign_in create(:user)

      expect do
        patch "/telemetry/settings/search_console_redirect", params: { search_console_redirect: { redirect_uri: override } }
      end.not_to(change { settings })
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "shows the field on the Search Console screen, blank, with the URL built from the host" do
      get "/telemetry/settings/google_connection"

      expect(page.at_css("label[for='search_console_redirect_redirect_uri']").text).to include("Redirect URL override")
      expect(field["value"]).to be_nil
      hint = page.at_css("##{field['aria-describedby']}").text.squish
      expect(hint).to include("https://example.com/telemetry/settings/google_callback", "the host under Settings, General")
    end

    it "saves an override and Google is sent it from then on" do
      patch "/telemetry/settings/search_console_redirect", params: { search_console_redirect: { redirect_uri: override } }

      expect(response).to redirect_to("/telemetry/settings/google_connection#redirect-url")
      expect(AhoyDashboard::SearchConsole.redirect_uri).to eq(override)

      follow_redirect!
      expect(field["value"]).to eq(override)
      expect(page.at_css("##{field['aria-describedby']}").text.squish).to include("the redirect URL saved on this screen")
    end

    it "goes back to building it from the host when cleared" do
      AhoyDashboard::Preferences.write(:search_console, redirect_uri: override)

      patch "/telemetry/settings/search_console_redirect", params: { search_console_redirect: { redirect_uri: " " } }

      expect(response).to redirect_to("/telemetry/settings/google_connection#redirect-url")
      expect(AhoyDashboard::Preferences.stored?(:search_console, :redirect_uri)).to be(false)
      expect(AhoyDashboard::SearchConsole.redirect_uri).to eq("https://example.com/telemetry/settings/google_callback")
    end

    it "refuses something that is not a full web address, names the field, and keeps the page" do
      expect do
        patch "/telemetry/settings/search_console_redirect",
              params: { search_console_redirect: { redirect_uri: "/telemetry/settings/google_callback" } }
      end.not_to(change { settings })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(page.at_css("[role='alert']").text.squish).to include("Redirect URL", "is not a full web address")
      expect(field["aria-invalid"]).to eq("true")
      expect(field["value"]).to eq("/telemetry/settings/google_callback")
      expect(response.body).to include("Setting it up in Google Cloud")
    end

    it "points at Settings, General when there is no host" do
      AhoyDashboard::Preferences.clear(:site, :host)

      get "/telemetry/settings/google_connection"

      hint = page.at_css("##{field['aria-describedby']}")
      expect(hint.text.squish).to include("no host set")
      expect(hint.css("a").map { |link| link["href"] }).to include("/telemetry/settings/general/edit")
      expect(page.css("a").map { |link| link["href"] }).to include("/telemetry/settings/general/edit")
      expect(response.body).not_to include("settings file")
    end

    it "points at Settings, General when the host is the example placeholder and the browser disagrees" do
      AhoyDashboard::Preferences.write(:site, host: "www.example.com")

      get "/telemetry/settings/google_connection", headers: { "Host" => "dash.fpd.example" }

      expect(page.text.squish).to include("still the example placeholder")
      expect(response.body).not_to include("settings file")
    end
  end
end
