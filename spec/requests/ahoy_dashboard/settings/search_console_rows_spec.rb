require "rails_helper"


RSpec.describe "Dashboard Search Console raw rows", type: :request do
  def row(date: Date.new(2026, 8, 3), query: "fci thomson visiting", page: "https://x/a", clicks: 3,
          impressions: 40, ctr: 0.075, position: 4.5)
    create(:dash_search_console_row, date: date, query: query, page: page, clicks: clicks,
           impressions: impressions, ctr: ctr, position: position)
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/search_console_rows"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "does not admit that it exists to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/search_console_rows"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "renders with nothing pulled" do
      get "/telemetry/settings/search_console_rows"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing pulled yet")
    end

    it "shows a row exactly as it landed" do
      row(query: "fci ray brook lockdown", clicks: 3, impressions: 14, ctr: 0.214, position: 3.4)

      get "/telemetry/settings/search_console_rows"

      expect(response.body).to include("fci ray brook lockdown")
      expect(response.body).to include("21.4%")
      expect(response.body).to include("3.4")
    end

    # The whole reason to show raw rows: the rows are a sample of the clicks, and
    # how small a sample is only visible beside the day's own total.
    describe "the per day summary" do
      it "prints the rows against what the day actually got" do
        row(clicks: 3)
        row(query: "another", clicks: 2)
        create(:dash_search_console_total, date: Date.new(2026, 8, 3), clicks: 50, impressions: 900)

        get "/telemetry/settings/search_console_rows"

        expect(response.body).to include("50")
        expect(response.body).to include("10.0%")
      end

      it "says a day was not pulled rather than calling it zero" do
        row

        get "/telemetry/settings/search_console_rows"

        expect(response.body).to include("not pulled")
      end

      it "adds up a day total that google split by device and country" do
        row(clicks: 5)
        create(:dash_search_console_total, date: Date.new(2026, 8, 3), device: "mobile", country: "usa",
                                           clicks: 30, impressions: 500)
        create(:dash_search_console_total, date: Date.new(2026, 8, 3), device: "desktop", country: "usa",
                                           clicks: 20, impressions: 400)

        get "/telemetry/settings/search_console_rows"

        expect(response.body).to include("10.0%")
      end

      it "counts a day that has a total but no rows" do
        create(:dash_search_console_total, date: Date.new(2026, 8, 4), clicks: 12, impressions: 100)

        get "/telemetry/settings/search_console_rows"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("12")
      end
    end

    it "names each row's device and country, and calls the older rows unknown" do
      create(:dash_search_console_row, date: Date.new(2026, 8, 3), query: "rdap", device: "mobile", country: "usa")
      row(query: "older")

      get "/telemetry/settings/search_console_rows"

      expect(response.body).to include("Mobile", "United States", "Unknown")
    end

    it "names a withheld query rather than showing an empty cell" do
      row(query: "")

      get "/telemetry/settings/search_console_rows"

      expect(response.body).to include("(anonymized)")
      expect(response.body).not_to include("(withheld)")
    end

    describe "finding one" do
      before do
        row(query: "fci thomson visiting")
        row(query: "halfway house rules", page: "https://x/b")
      end

      it "narrows to the matching rows" do
        get "/telemetry/settings/search_console_rows", params: { q: "thomson" }

        expect(response.body).to include("fci thomson visiting")
        expect(response.body).not_to include("halfway house rules")
      end

      it "matches on the page as well as the query" do
        get "/telemetry/settings/search_console_rows", params: { q: "/b" }

        expect(response.body).to include("halfway house rules")
      end

      it "treats a wildcard character as a character" do
        get "/telemetry/settings/search_console_rows", params: { q: "%" }

        expect(response.body).not_to include("fci thomson visiting")
      end

      it "says so when nothing matches" do
        get "/telemetry/settings/search_console_rows", params: { q: "nothing like this" }

        expect(response.body).to include("Nothing matches")
      end
    end

    describe "sorting and paging" do
      it "sorts by the column asked for" do
        row(query: "few clicks", clicks: 1, position: 90.0)
        row(query: "many clicks", clicks: 99, position: 2.0, page: "https://x/b")

        get "/telemetry/settings/search_console_rows", params: { sort: "position" }

        body = response.body
        expect(body.index("many clicks")).to be < body.index("few clicks")
      end

      it "falls back to the default sort and page rather than erroring" do
        row

        [ { sort: "nonsense" }, { page: "0" }, { page: "-3" }, { page: "banana" },
          { sort: "date; drop table" }, { q: "_" } ].each do |params|
          get "/telemetry/settings/search_console_rows", params: params

          expect(response).to have_http_status(:ok), "expected #{params.inspect} to render"
        end
      end

      it "pages, and keeps the search and the sort while it does" do
        105.times { |n| row(query: "term #{n}", page: "https://x/#{n}", clicks: n) }

        get "/telemetry/settings/search_console_rows", params: { q: "term", sort: "clicks" }

        expect(response.body).to include("Page 1 of 2")
        expect(response.body).to include("q=term")
        expect(response.body).to include("sort=clicks")
      end
    end

    it "is reachable from the connection screen once something is stored" do
      row
      create(:dash_search_console_total, date: Date.new(2026, 8, 3), clicks: 50, impressions: 900)

      get "/telemetry/settings/google_connection"

      expect(response.body).to include(AhoyDashboard::Engine.routes.url_helpers.settings_search_console_rows_path)
    end
  end
end
