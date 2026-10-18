require "rails_helper"

RSpec.describe "Dashboard serp site settings", type: :request do
  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "lists the sites and says which one is us" do
      allow(AhoyDashboard::Serp).to receive(:own_domain).and_return("example.com")
      create(:dash_serp_site, name: "Us", domain: "example.com")
      create(:dash_serp_site, name: "Them", domain: "rival.com")

      get "/telemetry/settings/serp_sites"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Us", "Them", "rival.com")
    end

    it "says so when there is nothing yet" do
      get "/telemetry/settings/serp_sites"

      expect(response.body).to include("No sites yet")
    end

    describe "the new site form" do
      def domain_value
        document.at_css("input#serp_site_domain")["value"]
      end

      before { allow(AhoyDashboard::Serp).to receive(:own_domain).and_return("example.com") }

      it "starts with this site's own domain" do
        get "/telemetry/settings/serp_sites/new"

        expect(domain_value).to eq("example.com")
      end

      it "starts blank once this site is already tracked" do
        create(:dash_serp_site, domain: "example.com")

        get "/telemetry/settings/serp_sites/new"

        expect(domain_value).to be_blank
      end
    end

    it "stores a domain with the scheme and the www taken off" do
      post "/telemetry/settings/serp_sites",
        params: { serp_site: { name: "Us", domain: "https://www.Example.com/path" } }

      expect(response).to redirect_to("/telemetry/settings/serp_sites")
      expect(sole_item(AhoyDashboard::SerpSite).domain).to eq("example.com")
    end

    it "rejects something that is not a domain" do
      post "/telemetry/settings/serp_sites", params: { serp_site: { name: "Us", domain: "  " } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::SerpSite.count).to be_zero
    end

    it "will not take the same domain twice" do
      create(:dash_serp_site, domain: "example.com")

      post "/telemetry/settings/serp_sites",
        params: { serp_site: { name: "Again", domain: "example.com" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("already")
    end

    it "edits one" do
      site = create(:dash_serp_site, name: "Old")

      patch "/telemetry/settings/serp_sites/#{site.id}",
        params: { serp_site: { name: "New", domain: site.domain, match_subdomains: "1" } }

      expect(site.reload.name).to eq("New")
      expect(site.match_subdomains).to be(true)
    end

    describe "what a site costs" do
      before { create(:dash_serp_site) }

      it "says sample results are free" do
        get "/telemetry/settings/serp_sites"

        expect(response.body).to include("Extra sites cost nothing. Sample results are free.")
      end

      it "says a provider that charges by the page charges by the page" do
        create(:dash_serp_provider, :serpapi, :active)

        get "/telemetry/settings/serp_sites"

        expect(response.body).to include("Each check is one search per place, per page of results.")
      end

      it "says DataForSEO charges one search per place however deep" do
        create(:dash_serp_provider, :active, name: "dataforseo")

        get "/telemetry/settings/serp_sites"

        expect(response.body).to include("Each check is one search per place, however deep.")
      end
    end

    describe "adding a site to the keywords" do
      let!(:keyword) { create(:dash_serp_keyword) }

      before { create(:dash_serp_run_page, run: create(:dash_serp_run, keyword: keyword)) }

      it "looks for a new site on every keyword and reads the saved searches for it" do
        post "/telemetry/settings/serp_sites",
          params: { serp_site: { name: "Rival", domain: "example.com", every_keyword: "1" } }

        site = AhoyDashboard::SerpSite.find_by!(domain: "example.com")
        expect(keyword.reload.sites).to eq([ site ])
        expect(sole_item(site.checks).position).to eq(2)
        expect(flash[:notice]).to include("added to 1 keyword", "1 past search was read again")
      end

      it "leaves the keywords alone when asked to" do
        post "/telemetry/settings/serp_sites",
          params: { serp_site: { name: "Rival", domain: "rival.com", every_keyword: "0" } }

        expect(keyword.reload.sites).to be_empty
        expect(flash[:notice]).to eq("Site saved.")
      end

      it "offers the choice on the new site form and not on the edit form" do
        get "/telemetry/settings/serp_sites/new"
        expect(response.body).to include("Look for it on every tracked keyword")

        get "/telemetry/settings/serp_sites/#{create(:dash_serp_site).id}/edit"
        expect(response.body).not_to include("Look for it on every tracked keyword")
      end

      it "reads a deleted site's positions back when it is added again" do
        post "/telemetry/settings/serp_sites", params: { serp_site: { name: "Rival", domain: "example.com" } }
        delete "/telemetry/settings/serp_sites/#{sole_item(AhoyDashboard::SerpSite).id}"
        expect(AhoyDashboard::SerpCheck.count).to be_zero

        post "/telemetry/settings/serp_sites", params: { serp_site: { name: "Rival", domain: "example.com" } }

        expect(sole_item(sole_item(AhoyDashboard::SerpSite).checks).position).to eq(2)
      end
    end

    it "asks before deleting, in the row" do
      site = create(:dash_serp_site, name: "Doomed")

      get "/telemetry/settings/serp_sites", params: { confirm: site.id }

      expect(response.body).to include("Delete", "Doomed")
    end

    it "deletes one and everything recorded about it" do
      check = create(:dash_serp_check)

      delete "/telemetry/settings/serp_sites/#{check.site_id}"

      expect(response).to redirect_to("/telemetry/settings/serp_sites")
      expect(AhoyDashboard::SerpCheck.count).to be_zero
    end
  end
end
