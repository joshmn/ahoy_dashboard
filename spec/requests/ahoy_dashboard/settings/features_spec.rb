require "rails_helper"
require "support/ahoy_dashboard/switches"
require "support/ahoy_dashboard/installation"

RSpec.describe "Dashboard features settings", type: :request do
  def row(name)
    Nokogiri::HTML5(response.body).at_css("#feature-#{name}")
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/features"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin, and switches nothing" do
      sign_in create(:user)

      patch "/telemetry/settings/features/serp", params: { enabled: "1" }

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::Features.on?(:serp)).to be(false)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "lists every feature with its state, and is in the settings nav" do
      switch_on_ahoy_dashboard(:alerts)

      get "/telemetry/settings/features"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/telemetry/settings/features"))
      AhoyDashboard::Features.all.each do |feature|
        expect(row(feature.name).text).to include(feature.label)
      end
      expect(row(:alerts).text).to include("Needs setup")
      expect(row(:alerts).at_css("button[aria-label='Turn off Alerts']")).to be_present
      expect(row(:serp).text).to include("Off")
      expect(row(:serp).at_css("button[aria-label='Turn on Rank tracking']")).to be_present
      expect(row(:favicons).text).to include("On")
    end

    it "links every feature with a screen to its settings, whether or not it is on" do
      switch_off_ahoy_dashboard(:serp)

      get "/telemetry/settings/features"

      {
        alerts: "/telemetry/settings/alert_rules", serp: "/telemetry/settings/serp_keywords",
        keywords: "/telemetry/settings/serp_providers", places: "/telemetry/settings/serp_providers",
        reports: "/telemetry/settings/emails/edit"
      }.each do |name, path|
        expect(row(name).at_css("a[href='#{path}']").text).to include("Settings")
      end
      expect(row(:favicons).css("a").map(&:text)).not_to include("Settings")
    end

    it "turns a feature on and off" do
      patch "/telemetry/settings/features/serp", params: { enabled: "1" }

      expect(response).to redirect_to("/telemetry/settings/features#feature-serp")
      expect(flash[:notice]).to eq("Rank tracking is on.")
      get "/telemetry/settings/features"
      expect(row(:serp).at_css("button[aria-label='Turn off Rank tracking']")).to be_present

      patch "/telemetry/settings/features/serp", params: { enabled: "0" }

      expect(flash[:notice]).to eq("Rank tracking is off.")
      get "/telemetry/settings/features"
      expect(row(:serp).at_css("button[aria-label='Turn on Rank tracking']")).to be_present
    end

    it "turns off a feature that is on by default" do
      patch "/telemetry/settings/features/favicons", params: { enabled: "0" }

      expect(AhoyDashboard::FaviconService.enabled?).to be(false)
    end

    it "shows a missing feature as not installed with its install command, and will not turn it on" do
      uninstall_ahoy_dashboard(:serp)

      get "/telemetry/settings/features"

      expect(row(:serp).text).to include("Not installed")
      expect(row(:serp).text).to include("bin/rails generate ahoy_dashboard:install --only serp")
      expect(row(:serp).at_css("button[disabled]")).to be_present

      patch "/telemetry/settings/features/serp", params: { enabled: "1" }

      expect(flash[:alert]).to eq("Rank tracking is not installed in this app yet.")
      expect(AhoyDashboard::Features.on?(:serp)).to be(false)
    end

    it "says what a feature that is on still needs, and links to where it is fixed" do
      switch_on_ahoy_dashboard(:serp, :alerts)

      get "/telemetry/settings/features"

      expect(row(:serp).text).to include("Needs setup", "Rankings are sample data until you choose a real search provider.")
      expect(row(:serp).at_css("a[href='/telemetry/settings/serp_providers']").text).to include("Set it up")
      expect(row(:alerts).text).to include("Needs setup", "No alert rules are switched on.")
      expect(row(:alerts).at_css("a[href='/telemetry/settings/alert_rules']")).to be_present
    end

    it "names the assistant's missing key in its own words" do
      switch_on_ahoy_dashboard(:assistant)
      allow(AhoyDashboard::Assistant).to receive_messages(model_name: "test-model", provider_ready?: false)

      get "/telemetry/settings/features"

      expect(row(:assistant).text).to include("Needs setup", AhoyDashboard::Assistant.unavailable_reason)
    end

    it "says nothing more about a feature that is on and set up" do
      switch_on_ahoy_dashboard(:alerts)
      create(:dash_alert_rule, key: "traffic_spike", name: "Traffic spike")
      allow(AhoyDashboard::Alerts::Digests).to receive_messages(periods: [ :daily ], recipients: [ "ops@example.com" ])

      get "/telemetry/settings/features"

      expect(row(:alerts).text).to include("On")
      expect(row(:alerts).text).not_to include("Needs setup", "Not set up yet")
    end

    it "says why when a check itself fails" do
      switch_on_ahoy_dashboard(:alerts)
      allow(AhoyDashboard::AlertRule).to receive(:live).and_raise(ActiveRecord::StatementInvalid)

      get "/telemetry/settings/features"

      expect(row(:alerts).text).to include("Could not check whether this is set up.")
    end

    it "404s a feature it does not know" do
      patch "/telemetry/settings/features/rankings", params: { enabled: "1" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
