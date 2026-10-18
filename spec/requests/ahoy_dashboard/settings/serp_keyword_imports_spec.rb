require "rails_helper"

RSpec.describe "Dashboard serp keyword imports", type: :request do
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  def searched(query, impressions:, clicks: 0, position: 12.0, on: Date.current - 3)
    create(:dash_search_console_keyword, query: query, impressions: impressions, clicks: clicks,
           position: position, date: on)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "offers the busiest search console queries, most impressions first" do
      searched("visiting hours", impressions: 40)
      searched("commissary list", impressions: 900)

      get "/telemetry/settings/serp_keyword_import/new"

      expect(response).to have_http_status(:ok)
      expect(response.body.index("commissary list")).to be < response.body.index("visiting hours")
    end

    it "leaves out a query that is already tracked" do
      searched("visiting hours", impressions: 900)
      create(:dash_serp_keyword, query: "visiting hours")

      get "/telemetry/settings/serp_keyword_import/new"

      expect(response.body).not_to include(">visiting hours")
    end

    it "says so when search console has nothing to offer" do
      get "/telemetry/settings/serp_keyword_import/new"

      expect(response.body).to include("Nothing to offer here")
    end

    it "imports the ticked ones and the pasted ones under one set of settings" do
      searched("commissary list", impressions: 900)

      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { selected: [ "commissary list" ],
                                         pasted: "visiting hours\r\nhalfway house rules\r\n",
                                         locations: "us", pages: "1", frequency: "weekly",
                                         device: "desktop", language: "en", engine: "google",
                                         site_ids: [ site.id.to_s ] } }

      expect(response).to redirect_to("/telemetry/settings/serp_keywords")
      expect(AhoyDashboard::SerpKeyword.pluck(:query))
        .to contain_exactly("commissary list", "visiting hours", "halfway house rules")
      expect(AhoyDashboard::SerpKeyword.pluck(:frequency).uniq).to eq([ "weekly" ])
      expect(AhoyDashboard::SerpKeyword.all.map { |k| k.sites.to_a }.flatten.uniq).to eq([ site ])
      expect(flash[:notice]).to include("3 keywords now tracked")
    end

    it "marks an imported keyword as having come from search console" do
      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { pasted: "visiting hours", locations: "us", pages: "1",
                                         frequency: "weekly", device: "desktop", language: "en",
                                         engine: "google" } }

      expect(sole_item(AhoyDashboard::SerpKeyword).source).to eq("search_console")
    end

    it "drops repeats inside the paste rather than failing" do
      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { pasted: "visiting hours\nVisiting Hours\n visiting hours ",
                                         locations: "us", pages: "1", frequency: "weekly",
                                         device: "desktop", language: "en", engine: "google" } }

      expect(AhoyDashboard::SerpKeyword.count).to eq(1)
    end

    it "counts one that is already tracked instead of refusing the batch" do
      create(:dash_serp_keyword, query: "visiting hours")

      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { pasted: "visiting hours\ncommissary list", locations: "us",
                                         pages: "1", frequency: "weekly", device: "desktop",
                                         language: "en", engine: "google" } }

      expect(AhoyDashboard::SerpKeyword.count).to eq(2)
      expect(flash[:notice]).to include("1 keyword now tracked", "1 were already on the list")
    end

    it "counts one tracked with other capitals as already tracked rather than paying for it twice" do
      create(:dash_serp_keyword, query: "Visiting Hours")

      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { pasted: "visiting hours\ncommissary list", locations: "us",
                                         pages: "1", frequency: "weekly", device: "desktop",
                                         language: "en", engine: "google" } }

      expect(AhoyDashboard::SerpKeyword.pluck(:query)).to contain_exactly("Visiting Hours", "commissary list")
      expect(flash[:notice]).to include("1 keyword now tracked", "1 were already on the list")
    end

    it "refuses an import with nothing in it" do
      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { pasted: "  ", locations: "us", pages: "1",
                                         frequency: "weekly", device: "desktop", language: "en",
                                         engine: "google" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("nothing to import")
    end

    it "refuses a place it cannot read rather than importing a hundred broken keywords" do
      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { pasted: "visiting hours", locations: "  \n ", pages: "1",
                                         frequency: "weekly", device: "desktop", language: "en",
                                         engine: "google" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::SerpKeyword.count).to be_zero
    end
  end
end
