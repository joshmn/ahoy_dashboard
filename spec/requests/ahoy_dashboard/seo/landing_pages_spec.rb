require "rails_helper"

RSpec.describe "Dashboard seo landing pages", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  def document
    Nokogiri::HTML5(response.body)
  end

  def reading(keyword, position:, url:, days_ago: 1, site: self.site)
    run = create(:dash_serp_run, keyword: keyword, checked_at: now - days_ago.days)
    create(:dash_serp_check, run: run, site: site, position: position, url: url)
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/seo/landing_page"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/seo/landing_page"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "asks for a site first" do
      get "/telemetry/seo/landing_page"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add your site to get started")
    end

    context "with readings" do
      let(:visiting) { create(:dash_serp_keyword, query: "visiting hours", tags: [ "guides" ]) }
      let(:consult) { create(:dash_serp_keyword, query: "prison consultant", tags: [ "Brand" ]) }
      let(:money) { create(:dash_serp_keyword, query: "commissary money") }

      before do
        reading(visiting, position: 1, url: "https://example.com/visiting")
        reading(consult, position: 4, url: "https://example.com/")
        reading(money, position: 6, url: "https://example.com/money", days_ago: 3)
        reading(money, position: nil, url: nil)
      end

      def table
        document.at_css("#landing-pages table")
      end

      it "lists one row per page with its searches, best, median and share" do
        get "/telemetry/seo/landing_page"

        rows = table.css("tbody > tr")
        expect(rows.map { |row| row.at_css("td a").text.squish }).to eq([ "/visiting", "/" ])
        first = rows.first.css("> td").map { |cell| cell.text.squish }
        expect(first[1..3]).to eq([ "1", "1", "1" ])
        expect(first.last).to match(/\A\d+\.\d%\z/)
      end

      it "opens a row to the searches it holds, each linked to its history" do
        get "/telemetry/seo/landing_page"

        held = table.at_css("tbody > tr details")
        expect(held.at_css("summary").text.squish).to include("1 search held")
        expect(held.at_css("a")["href"]).to include("/telemetry/rank_keyword?").and(include("keyword=#{visiting.id}"))
      end

      it "keeps a page that lost every search, with the searches listed as gone" do
        get "/telemetry/seo/landing_page"

        lost = document.at_css("#landing-pages-lost")
        expect(lost.at_css("h2").text.squish).to eq("Lost every search")
        expect(lost.text.squish).to include("/money", "commissary money", "Not in the results")
      end

      it "shows up on the rail under Rank tracking" do
        get "/telemetry/seo/landing_page"

        link = document.css("nav.seo-rail a").find { |node| node.text.squish == "Landing pages" }
        expect(link["aria-current"]).to eq("page")
      end

      it "reads one tag at a time" do
        get "/telemetry/seo/landing_page", params: { tag: "Brand" }

        expect(table.css("tbody > tr").map { |row| row.at_css("td a").text.squish }).to eq([ "/" ])
        expect(document.at_css("#landing-pages-lost")).to be_nil
        expect(document.at_css("#tm-seo-tag-button").text.squish).to eq("Tag: Brand")
      end

      it "reads another site from the site menu" do
        rival = create(:dash_serp_site, name: "Them", domain: "rival.com")
        reading(visiting, position: 2, url: "https://rival.com/hours", site: rival)

        get "/telemetry/seo/landing_page", params: { site: rival.id }

        expect(document.at_css("h1").text.squish).to eq("Landing pages: Them")
        expect(table.css("tbody > tr").map { |row| row.at_css("td a").text.squish }).to eq([ "/hours" ])
      end
    end
  end
end
