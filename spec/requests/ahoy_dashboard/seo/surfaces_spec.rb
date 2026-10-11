require "rails_helper"

RSpec.describe "Dashboard seo surfaces", type: :request do
  let(:paths) { AhoyDashboard::Seo::Surface::ALL.map { |surface| [ surface.key, surface.path ] } }

  describe "gating" do
    it "sends a signed out visitor to sign in from every surface" do
      paths.each do |key, path|
        get path

        expect(response).to redirect_to("/users/sign_in"), "expected #{key} to bounce a signed out visitor"
      end
    end

    it "does not admit any of them exists to a signed in visitor who is not an admin" do
      paths.each do |key, path|
        sign_in create(:user)

        get path

        expect(response).to have_http_status(:not_found), "expected #{key} to 404"
      end
    end
  end

  describe "with nothing on file" do
    before { sign_in create(:user, :admin) }

    it "renders the overview with the set up checklist" do
      get "/telemetry/seo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Set up", "Connect Search Console", "Track keyword")
      expect(response.body).not_to include("surfaces")
    end

    it "puts every page in the rail and marks the one that is open" do
      get AhoyDashboard::Seo::Surface.find("visibility").path
      document = Nokogiri::HTML5(response.body)

      expect(document.css(".seo-rail a").size).to eq(AhoyDashboard::Seo::Surface::ALL.size + 1)
      expect(document.at_css(".seo-rail a[aria-current=page] .seo-rail__label").text.strip).to eq("Visibility")
    end

    it "points an empty rank tracking page at adding a site first" do
      get AhoyDashboard::Seo::Surface.find("position_changes").path

      expect(response.body).to include("Add your site to get started", "/telemetry/settings/serp_sites/new")
    end

    it "asks for keywords once a site is on file" do
      create(:dash_serp_site)

      get AhoyDashboard::Seo::Surface.find("visibility").path

      expect(response.body).to include("Add your keywords to get started", "/telemetry/settings/serp_keywords/new")
    end

    it "asks for a competitor on keyword gap once rank tracking is set up" do
      create(:dash_serp_keyword_target)

      get AhoyDashboard::Seo::Surface.find("keyword_gap").path

      expect(response.body).to include("Add a competitor to get started", "/telemetry/settings/serp_sites/new")
    end

    it "keeps commands and config keys off the page" do
      get AhoyDashboard::Seo::Surface.find("backlinks").path

      expect(response.body).not_to include("rails ahoy_dashboard", "config.")
    end

    it "does not print an error-like line on an empty keyword research page" do
      get AhoyDashboard::Seo::Surface.find("keyword_research").path

      expect(response.body).not_to include("can't answer")
    end

    it "says in one notice that alerts are off, with a way to the rules" do
      get AhoyDashboard::Seo::Surface.find("alerts").path

      expect(response.body).to include("Alerts are off", "/telemetry/settings/alert_rules")
      expect(response.body).not_to include("config.alert")
    end

    it "keeps each paid action on the page, disabled, with the reason beside it" do
      {
        "alerts" => [ "Check now", "Alerts are off" ],
        "backlinks" => [ "Sync now", "Backlinks are off" ],
        "keyword_research" => [ "Look up", "Keyword research is off" ]
      }.each do |key, (label, why)|
        get AhoyDashboard::Seo::Surface.find(key).path
        document = Nokogiri::HTML5(response.body)
        button = document.css("button[disabled][aria-describedby]").find { |node| node.text.strip == label }

        expect(button).to be_present, "expected #{label} on #{key} to stay on the page"
        expect(document.at_css("##{button['aria-describedby']}").text).to include(why)
      end
    end

    it "renders every surface rather than erroring on an empty table" do
      paths.each do |key, path|
        get path

        expect(response).to have_http_status(:ok), "expected #{key} at #{path} to render"
      end
    end
  end

  describe "with something on file" do
    before do
      sign_in create(:user, :admin)

      site = create(:dash_serp_site, domain: AhoyDashboard::Serp.own_domain, name: "Us")
      keyword = create(:dash_serp_keyword)
      run = create(:dash_serp_run, keyword: keyword)
      create(:dash_serp_check, run: run, keyword: keyword, site: site, position: 4)
      create(:dash_search_console_total)
      create(:dash_search_console_keyword)
      create(:dash_search_console_row)
      create(:dash_alert_event)
    end

    it "renders every surface" do
      paths.each do |key, path|
        get path

        expect(response).to have_http_status(:ok), "expected #{key} at #{path} to render"
      end
    end
  end

  describe "serp features off a dataforseo reading" do
    before { sign_in create(:user, :admin) }

    it "renders the questions google asked and who answers them" do
      run = create(:dash_serp_run, provider: "dataforseo")
      create(:dash_serp_run_page, run: run, response: {
        "tasks" => [ { "id" => "task-1", "result" => [ { "keyword" => run.query, "items" => [
          { "type" => "people_also_ask", "items" => [
            { "type" => "people_also_ask_element", "title" => "Is FCI Thomson a max?",
              "expanded_element" => [
                { "type" => "people_also_ask_expanded_element", "url" => "https://www.bop.gov/tom",
                  "domain" => "www.bop.gov", "description" => "A medium." }
              ] }
          ] }
        ] } ] } ]
      })

      get AhoyDashboard::Seo::Surface.find("serp_features").path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Is FCI Thomson a max?", "bop.gov")
    end
  end

  describe "the made up numbers warning" do
    before { sign_in create(:user, :admin) }

    it "goes on a surface whose figures come from the serp provider" do
      get AhoyDashboard::Seo::Surface.find("visibility").path

      expect(response.body).to include("These are sample results")
    end

    it "stays off a surface reading tables google filled in" do
      get AhoyDashboard::Seo::Surface.find("opportunities").path

      expect(response.body).not_to include("These are sample results")
    end

    it "comes off once a paid provider is answering" do
      allow(AhoyDashboard::Serp).to receive(:provider).and_return(:dataforseo)

      get AhoyDashboard::Seo::Surface.find("visibility").path

      expect(response.body).not_to include("These are sample results")
    end
  end

  describe "the stopped syncing warning" do
    before do
      sign_in create(:user, :admin)
      allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(true)
      create(:dash_google_account, :with_property, last_error: "Google would not hand back an access token.")
    end

    it "goes on a surface reading what google sent, with the reason and the way to fix it" do
      get AhoyDashboard::Seo::Surface.find("opportunities").path
      notice = Nokogiri::HTML5(response.body).css("[role=status]").find { |node| node.text.include?("not syncing") }

      expect(notice.text.squish).to eq("Search Console is not syncing. Google would not hand back an access token. Fix connection")
      expect(notice.at_css("a")["href"]).to eq(AhoyDashboard::Engine.routes.url_helpers.settings_google_connection_path)
    end

    it "stays off a surface that reads only rank checks" do
      get AhoyDashboard::Seo::Surface.find("position_changes").path

      expect(response.body).not_to include("Search Console is not syncing")
    end
  end
end
