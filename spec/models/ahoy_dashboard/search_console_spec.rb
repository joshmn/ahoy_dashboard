require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole do
  describe ".enabled?" do
    it "is off by default in test" do
      expect(described_class).not_to be_enabled
    end

    it "needs the switch and both halves of the stored client" do
      store_google_client(client_id: "cid", client_secret: "secret")
      search_console_settings(enabled: true) { expect(described_class).to be_enabled }

      store_google_client(client_id: "cid", client_secret: nil)
      search_console_settings(enabled: true) { expect(described_class).not_to be_enabled }

      store_google_client(client_id: "cid", client_secret: "secret")
      search_console_settings(enabled: false) { expect(described_class).not_to be_enabled }
    end

    it "stays off until switched on, even with the client stored" do
      store_google_client(client_id: "cid", client_secret: "secret")

      expect(described_class).not_to be_enabled
    end

    it "reads the client from what is stored and nowhere else" do
      allow(Rails.application.credentials).to receive(:search_console_client_id).and_return("from-credentials")
      expect(described_class.client_id).to be_nil

      store_google_client(client_id: "cid", client_secret: "secret")

      expect(described_class.client_id).to eq("cid")
      expect(described_class.client_secret).to eq("secret")
    end
  end

  describe ".redirect_uri" do
    it "falls back to the canonical host and the callback route" do
      expect(described_class.redirect_uri)
        .to eq("https://example.com/telemetry/settings/google_callback")
    end

    it "is nil rather than raising when no host is set anywhere" do
      AhoyDashboard::Preferences.clear(:site, :host, :canonical_host)

      search_console_settings(redirect_uri: nil) do
        expect(described_class.redirect_uri).to be_nil
      end
    end

    it "builds it from the canonical host when one is set apart from the host" do
      AhoyDashboard::Preferences.write(:site, canonical_host: "www.fpd.example")

      expect(described_class.redirect_uri).to eq("https://www.fpd.example/telemetry/settings/google_callback")
    end

    it "prefers the configured one, because google only allows plain http on localhost" do
      search_console_settings(redirect_uri: "http://localhost:5000/telemetry/settings/google_callback") do
        expect(described_class.redirect_uri).to eq("http://localhost:5000/telemetry/settings/google_callback")
      end
    end
  end

  describe ".authorization_url" do
    it "asks for offline access and consent, which is what gets a refresh token" do
      search_console_enabled!

      params = URI.decode_www_form(URI(described_class.authorization_url(state: "abc123")).query).to_h

      expect(params).to include(
        "client_id" => SearchConsoleFixtures::CLIENT_ID,
        "redirect_uri" => SearchConsoleFixtures::REDIRECT_URI,
        "response_type" => "code",
        "scope" => described_class::SCOPE,
        "access_type" => "offline",
        "prompt" => "consent",
        "include_granted_scopes" => "true",
        "state" => "abc123"
      )
    end

    it "asks for read only search console and nothing else" do
      expect(described_class::SCOPE).to eq("https://www.googleapis.com/auth/webmasters.readonly")
    end
  end

  describe ".analytics_url" do
    it "percent encodes a domain property verbatim rather than tidying it up" do
      expect(described_class.analytics_url("sc-domain:example.com"))
        .to eq("https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query")
    end

    it "encodes a url prefix property" do
      expect(described_class.analytics_url("https://example.com/"))
        .to eq("https://www.googleapis.com/webmasters/v3/sites/https%3A%2F%2Fexample.com%2F/searchAnalytics/query")
    end
  end

  describe "dates" do
    around { |example| travel_to(Time.utc(2026, 8, 12, 18, 0)) { example.run } }

    it "reads days in pacific time, because that is how search console cuts them" do
      expect(described_class.today).to eq(Date.new(2026, 8, 12))
    end

    it "treats three days back as the last finished day" do
      expect(described_class.latest_final_date).to eq(Date.new(2026, 8, 9))
    end

    it "re-reads a trailing week on every run" do
      expect(described_class.ingest_dates).to eq((Date.new(2026, 8, 3)..Date.new(2026, 8, 9)).to_a)
    end
  end
end
