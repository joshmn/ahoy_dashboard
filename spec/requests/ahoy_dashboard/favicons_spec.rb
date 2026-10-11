require "rails_helper"
require "support/ahoy_dashboard/fixtures"
require "support/ahoy_dashboard/switches"

RSpec.describe "Dashboard favicons", type: :request do
  let(:png) { "\x89PNG\r\n\x1a\n".b + "the rest of it".b }
  let(:icon_url) { "https://icons.duckduckgo.com/ip3/google.com.ico" }

  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = previous
  end

  before { dash_visit(started_at: Time.current, referring_domain: "google.com") }

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/favicons/google.com"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/favicons/google.com"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "serves the bytes with the type the bytes say they are" do
      stub_request(:get, icon_url).to_return(status: 200, body: png,
        headers: { "Content-Type" => "text/plain" })
      AhoyDashboard::FaviconService.call("google.com")

      get "/telemetry/favicons/google.com"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.body.b).to eq(png)
    end

    it "tells the browser to stop asking, and no shared cache to keep it" do
      stub_request(:get, icon_url).to_return(status: 200, body: png)
      AhoyDashboard::FaviconService.call("google.com")

      get "/telemetry/favicons/google.com"

      expect(response.headers["Cache-Control"]).to include("max-age=604800", "private")
    end

    it "404s for a domain nothing in the data referred us from" do
      get "/telemetry/favicons/evil.example"

      expect(response).to have_http_status(:not_found)
      expect(WebMock).not_to have_requested(:get, %r{icons\.duckduckgo\.com})
    end

    it "keeps the letter visible while a known icon has not been cached" do
      get "/telemetry/favicons/google.com"

      expect(response.body.b).to eq(AhoyDashboard::FaviconsController::FALLBACK)
    end

    it "queues a cache miss without waiting for the icon host" do
      expect { get "/telemetry/favicons/google.com" }.to have_enqueued_job(AhoyDashboard::FaviconFetchJob).with("google.com")
    end

    it "does not enqueue another fetch while the first one is pending" do
      get "/telemetry/favicons/google.com"

      expect { get "/telemetry/favicons/google.com" }.not_to have_enqueued_job(AhoyDashboard::FaviconFetchJob)
    end

    it "does not fetch synchronously when the host executes jobs inline" do
      previous = AhoyDashboard::FaviconFetchJob.queue_adapter
      AhoyDashboard::FaviconFetchJob.queue_adapter = :inline
      get "/telemetry/favicons/google.com"

      expect(response.body.b).to eq(AhoyDashboard::FaviconsController::FALLBACK)
    ensure
      AhoyDashboard::FaviconFetchJob.queue_adapter = previous
    end

    it "does not enqueue work when the host has no cache" do
      Rails.cache = ActiveSupport::Cache::NullStore.new

      expect { get "/telemetry/favicons/google.com" }.not_to have_enqueued_job(AhoyDashboard::FaviconFetchJob)
    end

    # The row keeps its letter underneath the icon rather than swapping one for
    # the other, so a domain with no icon, one still in flight and the whole
    # thing switched off all read the same and none of them reflow the row.
    describe "on a source row" do
      before do
        visit = dash_visit(started_at: Time.current, visitor: "one",
          referring_domain: "google.com", referrer: "https://www.google.com/")
        dash_page_view(visit, path: "/alpha")
      end

      def source_card
        get "/telemetry/reports/sources", params: { tab: "sources" }
        Nokogiri::HTML5(response.body)
      end

      it "points the icon at our own host and leaves the letter behind it" do
        chip = source_card.at_css(".lc--icon")

        expect(chip.at_css(".lc__letter").text).to eq("g")
        expect(chip.at_css("img")["src"]).to eq("/telemetry/favicons/google.com")
        expect(chip.at_css("img")["alt"]).to eq("")
        expect(chip["aria-hidden"]).to eq("true")
      end

      it "draws a channel with its glyph rather than a favicon" do
        get "/telemetry/reports/sources", params: { tab: "channels" }
        document = Nokogiri::HTML5(response.body)

        expect(document.at_css(".lc--icon")).to be_nil
        expect(document.at_css(".lc--glyph svg|svg", "svg" => "http://www.w3.org/2000/svg")).to be_present
      end

      it "falls back to the letter alone while switched off" do
        switch_off_ahoy_dashboard(:favicons)

        expect(source_card.at_css(".lc--icon")).to be_nil
      end
    end

    it "404s while switched off, and asks nobody" do
      switch_off_ahoy_dashboard(:favicons)

      get "/telemetry/favicons/google.com"

      expect(response).to have_http_status(:not_found)
      expect(WebMock).not_to have_requested(:get, %r{icons\.duckduckgo\.com})
    end
  end
end
