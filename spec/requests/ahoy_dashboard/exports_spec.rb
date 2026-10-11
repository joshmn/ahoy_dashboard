require "rails_helper"
require "support/ahoy_dashboard/fixtures"
require "csv"

RSpec.describe "Dashboard exports", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def traffic!
    %w[/a /b /c].each_with_index do |path, index|
      visit = dash_visit(started_at: now - 1.day - index.minutes, visitor: "visitor-#{index}",
                              country: "US", browser: "Chrome")
      dash_page_view(visit, path: path, at: now - 1.day - index.minutes)
    end
  end

  def rows
    CSV.parse(response.body)
  end

  # The card shows nine rows and the details modal a hundred. The download is
  # the whole answer, and nothing in the path is allowed to quietly shorten it.
  describe "the whole answer" do
    before { sign_in create(:user, :admin) }

    it "carries every row, not a page of them" do
      40.times do |n|
        visit = dash_visit(started_at: now - 1.day - n.minutes, visitor: "v#{n}")
        dash_page_view(visit, path: "/p#{n}", at: now - 1.day - n.minutes)
      end

      get "/telemetry/exports/pages"

      expect(rows.size).to eq(41)  # a header and forty pages
    end

    # The body is handed over as an enumerator rather than a built string. The
    # rack stack under a request spec drains it and puts a length back on, so
    # what is checkable here is the download's own headers; that it goes out a
    # row at a time is only visible against a real server.
    it "asks proxies not to buffer, and downloads as a file" do
      traffic!

      get "/telemetry/exports/pages"

      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Accel-Buffering"]).to eq("no")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.media_type).to eq("text/csv")
    end
  end

  it "sends a signed out visitor to sign in" do
    get "/telemetry/exports/pages"

    expect(response).to redirect_to("/users/sign_in")
  end

  it "is a 404 for a signed in visitor who is not an admin" do
    sign_in create(:user)

    get "/telemetry/exports/pages"

    expect(response).to have_http_status(:not_found)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "sends a csv attachment named after the report and the day" do
      traffic!

      get "/telemetry/exports/pages"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("ahoy-dashboard-pages-2026-08-11.csv")
    end

    it "heads the label column with the tab's own heading and then the detail metrics" do
      traffic!
      tab = AhoyDashboard::Report.find("pages").tab("pages")

      get "/telemetry/exports/pages"

      expect(rows.first.first).to eq(tab.label_column)
      expect(rows.first.drop(1)).to eq(tab.detail_metrics.map { |key| AhoyDashboard::Metric.find(key).label })
    end

    it "writes one row per breakdown row under the header" do
      traffic!

      get "/telemetry/exports/pages"

      expect(rows.size).to eq(4)
      expect(rows.drop(1).map(&:first)).to match_array(%w[/a /b /c])
    end

    it "exports the tab it is asked for" do
      traffic!

      get "/telemetry/exports/locations", params: { tab: "countries" }

      expect(response).to have_http_status(:ok)
      expect(rows.size).to eq(2)
      expect(rows.last.first).to eq("United States")
    end

    it "exports every report key" do
      traffic!

      AhoyDashboard::Report.card_order.each do |key|
        get "/telemetry/exports/#{key}"

        expect(response).to have_http_status(:ok), "expected the #{key} export to render"
      end
    end

    it "writes a header and nothing else against an empty database" do
      get "/telemetry/exports/pages"

      expect(response).to have_http_status(:ok)
      expect(rows.size).to eq(1)
    end

    it "404s for a report key nobody registered" do
      get "/telemetry/exports/hairstyles"

      expect(response).to have_http_status(:not_found)
    end

    # A download that quietly reports a different grouping than the card it came
    # from is worse than no download, so the export resolves the card's own
    # dimension overrides exactly the way the card did.
    describe "the card's own dimension overrides" do
      it "groups by the breakdown the card was showing" do
        traffic!

        get "/telemetry/exports/pages", params: { tab: "pages", breakdown: "controller" }

        expect(rows.first.first).to eq("Rails controller")
        expect(rows.drop(1).map(&:first)).to eq([ "public/pages" ])
      end

      it "groups by the hostname on entry pages" do
        traffic!

        get "/telemetry/exports/pages", params: { tab: "entry_pages", breakdown: "host" }

        expect(rows.first.first).to eq("Hostname")
        expect(rows.drop(1).map(&:first)).to eq([ "federalprisondude.com" ])
      end

      it "groups by the property the card was showing" do
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-p")
        dash_page_view(visit, path: "/a", at: now - 1.day)
        create(:dash_property, key: "facility_id", position: 1)

        get "/telemetry/exports/behaviours", params: { tab: "properties", property: "action" }

        expect(rows.drop(1).map(&:first)).to eq([ "show" ])
      end

      it "falls back to the default rather than 500ing on a malformed value" do
        traffic!

        [ { breakdown: "banana" }, { breakdown: [ "url" ] }, { property: "not a key" },
          { property: "a" * 41 }, { breakdown: "", property: "" } ].each do |params|
          get "/telemetry/exports/pages", params: params.merge(tab: "pages")

          expect(response).to have_http_status(:ok), "expected #{params.inspect} to still export"
          expect(rows.first.first).to eq("Page url")
          expect(rows.drop(1).map(&:first)).to match_array(%w[/a /b /c])
        end
      end
    end

    it "honours the dashboard's period and filters" do
      traffic!

      get "/telemetry/exports/pages", params: {
        period: "7d", filters: [ { dimension: "page", operator: "is", value: "/a" } ]
      }

      expect(rows.drop(1).map(&:first)).to eq([ "/a" ])
    end
  end
end
