require "rails_helper"

RSpec.describe "Dashboard search console card", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }
  let(:day) { (now - 5.days).to_date }

  around { |example| travel_to(now) { example.run } }

  def connect!
    create(:dash_google_account, :with_property)
  end

  def rows!
    [ :dash_search_console_row, :dash_search_console_keyword ].each do |factory|
      create(factory, date: day, query: "fci thomson visiting", clicks: 6, impressions: 90, ctr: 0.066, position: 4.2)
      create(factory, date: day, query: "halfway house rules", clicks: 2, impressions: 30, ctr: 0.066, position: 11.5)
    end
    create(:dash_search_console_total, date: day, clicks: 12, impressions: 200,
           ctr: 0.06, position: 9.1)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "says Search Console is not connected and points at the settings screen" do
      get "/telemetry/search_console"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Connect Google Search Console to get started")
      expect(response.body).to include(AhoyDashboard::Engine.routes.url_helpers.settings_google_connection_path)
      expect(response.body).not_to include("Details")
    end

    it "reports a connection refusal recorded by the background refresh" do
      search_console_enabled!
      account = create(:dash_google_account, :with_property)
      account.record_error!(AhoyDashboard::SearchConsole::RefreshTokenService::REFUSED_MESSAGE)
      rows!

      get "/telemetry/search_console"
      note = document.css("p").find { |line| line.text.include?("not syncing") }

      expect(note.text.squish).to eq("Search Console is not syncing, so the newest days may be missing. Fix connection")
      expect(note.at_css("a")["href"]).to eq(AhoyDashboard::Engine.routes.url_helpers.settings_google_connection_path)
      expect(account.reload.last_error).to eq(AhoyDashboard::SearchConsole::RefreshTokenService::REFUSED_MESSAGE)
    end

    it "asks for a property when Google is connected without one" do
      create(:dash_google_account)

      get "/telemetry/search_console"

      expect(response.body).to include("Pick a Search Console property to get started",
                                       AhoyDashboard::Engine.routes.url_helpers.edit_settings_search_console_property_path)
    end

    it "blames the lag rather than the traffic when the connection is up and nothing is stored" do
      connect!

      get "/telemetry/search_console"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("two to three days late")
      expect(response.body).not_to include("Connect Google Search Console to get started")
    end

    it "says how far the data runs when the range reaches past it" do
      connect!
      rows!

      get "/telemetry/search_console"

      expect(response.body).to include("Data runs through Aug 6.")

      get "/telemetry/search_console", params: { view: "details" }

      expect(response.body).to include("Data runs through Aug 6.")
    end

    it "says nothing about how far the data runs when it reaches the end of the range" do
      connect!
      rows!
      create(:dash_search_console_total, date: now.to_date, clicks: 1, impressions: 10)

      get "/telemetry/search_console"

      expect(response.body).not_to include("Data runs through")
    end

    it "renders the card inside its own frame" do
      connect!
      rows!

      get "/telemetry/search_console"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="report_search_console"))
      expect(response.body).to include("fci thomson visiting")
      expect(response.body).to include("halfway house rules")
    end

    it "keeps the gap off the card" do
      connect!
      rows!

      get "/telemetry/search_console"

      expect(response.body).not_to include("Google hides searches that were rare")
      expect(response.body).not_to include("clicks have no query")
    end

    it "explains the gap in the drilldown, where the rows it is about are" do
      connect!
      rows!

      get "/telemetry/search_console", params: { view: "details" }

      expect(response.body).to include("Google hides searches that were rare")
      expect(response.body).to include("only sends the ones with the most clicks")
      expect(response.body).to include("4 clicks have no query")
    end

    it "leaves the coverage note off when the rows account for every click" do
      connect!
      create(:dash_search_console_row, date: day, query: "camp packing list", clicks: 12,
             impressions: 200, ctr: 0.06, position: 9.1)
      create(:dash_search_console_total, date: day, clicks: 12, impressions: 200,
             ctr: 0.06, position: 9.1)

      get "/telemetry/search_console", params: { view: "details" }

      expect(response.body).not_to include("clicks have no query")
    end

    it "shows a withheld query as anonymized rather than dropping the row" do
      connect!
      create(:dash_search_console_row, date: day, query: "", clicks: 4, impressions: 50)
      create(:dash_search_console_keyword, date: day, query: "", clicks: 4, impressions: 50)

      get "/telemetry/search_console"

      expect(response.body).to include("(anonymized)")
      expect(response.body).to include("data-row data-row--static")
    end

    it "opens a query row into that keyword's own history" do
      connect!
      rows!

      get "/telemetry/search_console"

      expect(response.body).to match(/<a[^>]*class="data-row"/)
      expect(response.body).to include("q=fci+thomson+visiting")
    end

    it "leaves a page row static, because a page has no series of its own" do
      connect!
      rows!

      get "/telemetry/search_console", params: { tab: "pages" }

      expect(response.body).to include("data-row data-row--static")
      expect(response.body).not_to match(/<a[^>]*class="data-row"/)
    end

    it "opens on the queries tab" do
      connect!
      rows!

      get "/telemetry/search_console"
      tabs = document.css('[data-controller="dash--tabs"] nav a')

      expect(tabs.find { |tab| tab["aria-current"] == "true" }.text.strip).to eq("Queries")
    end

    it "breaks down by page on the pages tab" do
      connect!
      rows!

      get "/telemetry/search_console", params: { tab: "pages" }

      tabs = document.css('[data-controller="dash--tabs"] nav a')

      expect(response).to have_http_status(:ok)
      expect(tabs.find { |tab| tab["aria-current"] == "true" }.text.strip).to eq("Pages")
      expect(response.body).to include("https://example.com/going-in/faq")
    end

    it "falls back to the queries tab on a tab that does not exist" do
      connect!
      rows!

      get "/telemetry/search_console", params: { tab: "banana" }
      tabs = document.css('[data-controller="dash--tabs"] nav a')

      expect(response).to have_http_status(:ok)
      expect(tabs.find { |tab| tab["aria-current"] == "true" }.text.strip).to eq("Queries")
      expect(response.body).to include("fci thomson visiting")
    end

    it "renders the details view into the details frame as the full list" do
      connect!
      rows!

      get "/telemetry/search_console", params: { view: "details" }
      document = Nokogiri::HTML5(response.body)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="report_details_search_console"))
      expect(response.body).not_to include(%(id="report_search_console"))
      expect(document.css(".m-list .data-row")).to be_present
      expect(document.at_css(".m-list").text).to include("fci thomson visiting")
      expect(document.at_css(".m-list").text).to include("halfway house rules")
    end

    it "renders the details view when nothing is connected" do
      get "/telemetry/search_console", params: { view: "details" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Connect Google Search Console to get started")
      expect(response.body).to include(AhoyDashboard::Engine.routes.url_helpers.settings_google_connection_path)
    end

    it "says filters do not reach search data when one is applied" do
      connect!
      rows!

      get "/telemetry/search_console",
        params: { filters: [ { dimension: "page", operator: "is", value: "/going-in/faq" } ] }

      expect(response.body).to include("Filters do not reach search data")
    end

    it "renders every period without falling over" do
      connect!
      rows!

      AhoyDashboard::Period::ALL.each do |period|
        get "/telemetry/search_console", params: { period: period.key, from: "2026-07-01", to: "2026-07-31" }

        expect(response).to have_http_status(:ok), "expected the #{period.key} period to render"
      end
    end
  end

  describe "the json format" do
    before { sign_in create(:user, :admin) }

    it "returns the rows, the totals and the coverage" do
      connect!
      rows!

      get "/telemetry/search_console.json"

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)

      expect(payload["tab"]).to eq("queries")
      expect(payload["connected"]).to be(true)
      expect(payload["rows"].map { |row| row["label"] }).to include("fci thomson visiting")
      expect(payload["totals"]["clicks"]).to eq(12)
      expect(payload["coverage"]["total_clicks"]).to eq(12)
      expect(payload["coverage"]["counted_clicks"]).to eq(8)
    end

    it "returns json with nothing connected" do
      get "/telemetry/search_console.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["connected"]).to be(false)
    end
  end

  describe "on the dashboard" do
    before { sign_in create(:user, :admin) }

    it "puts a lazy frame in the grid and a dialog beside the cards" do
      get "/telemetry"

      expect(response.body).to include(%(src="/telemetry/search_console))
      expect(response.body).to include(%(id="tm-modal-search_console"))
      expect(response.body).to include(%(id="report_details_search_console"))
      expect(document.at_css("tm-frame#report_search_console")["loading"]).to eq("lazy")
    end

    describe "disconnected with rows already stored" do
      before { rows! }

      it "still shows the stored rows" do
        get "/telemetry/search_console"

        expect(response.body).to include("fci thomson visiting")
        expect(response.body).not_to include("Set up Search Console")
      end

      it "says nothing new is arriving, and why" do
        get "/telemetry/search_console"

        expect(response.body).to include("Google is not connected, so nothing new is arriving")
      end

      it "still lists the stored rows in the details modal" do
        get "/telemetry/search_console", params: { view: "details" }

        expect(document.at_css(".m-list").text).to include("fci thomson visiting")
      end

      it "keeps the tab strip, so the pages side is still reachable" do
        get "/telemetry/search_console", params: { tab: "pages" }

        expect(response.body).to include("nav-link")
      end
    end

    describe "titles" do
      it "does not repeat the active tab label as the card title" do
        connect!
        rows!

        get "/telemetry/search_console"

        expect(response.body).to include("Google search")
        expect(response.body).to include(">Queries<")
      end
    end
  end
end
