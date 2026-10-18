require "rails_helper"

RSpec.describe "Dashboard seo pages with a feature not installed", type: :request do
  before { sign_in create(:user, :admin) }

  def rail_links
    document.css("nav[aria-label='SEO pages'] a")
  end

  def rail_paths
    rail_links.map { |link| link["href"].split("?").first }
  end

  def rail_link(path)
    rail_links.find { |link| link["href"].split("?").first == path }
  end

  def surface_paths(*features)
    AhoyDashboard::Seo::Surface::ALL.select { |surface| (surface.features & features).any? }.map(&:path)
  end

  def install_command(feature)
    "bin/rails generate ahoy_dashboard:install --only #{feature}"
  end

  def missing_tables_read(*features)
    tables = AhoyDashboardInstallation.tables_for(features)
    sql = captured_sql(cached: true) { yield }.reject { |statement| statement.include?("pg_class") }

    tables.select { |table| sql.any? { |statement| statement.include?(table) } }
  end

  def disabled_with_reason(label, reason)
    button = document.css("button[disabled]").find { |node| node.text.squish == label }
    expect(button).to be_present, "expected a disabled #{label} button"
    expect(document.at_css("##{button["aria-describedby"]}").text).to eq(reason)
  end

  describe "a page whose feature is missing" do
    AhoyDashboard::Seo::Surface::ALL.each do |surface|
      it "shows #{surface.key} inside the SEO rail with how to install #{surface.features.to_sentence}" do
        uninstall_ahoy_dashboard(*surface.features)

        read = missing_tables_read(*surface.features) { get surface.path }

        expect(response).to have_http_status(:ok)
        expect(read).to be_empty
        expect(document.at_css("h1").text.squish).to eq(surface.title)
        expect(response.body).to include(install_command(surface.features.first), "bin/rails db:migrate")
        expect(rail_link(surface.path)["aria-current"]).to eq("page")
      end
    end

    {
      serp: [ "/telemetry/rank_keyword?keyword=1", "/telemetry/rank_keyword?q=visiting+hours" ],
      search_console: [ "/telemetry/search_console_keyword?q=visiting+hours", "/telemetry/search_console" ],
      ai_visibility: [ "/telemetry/seo/ai_visibility/prompts/1" ]
    }.each do |feature, paths|
      paths.each do |path|
        it "shows how to install #{feature} on #{path}" do
          uninstall_ahoy_dashboard(feature)

          read = missing_tables_read(feature) { get path }

          expect(response).to have_http_status(:ok)
          expect(read).to be_empty
          expect(response.body).to include(install_command(feature))
        end
      end
    end

    {
      serp: [
        [ :post, "/telemetry/rank_check", {} ],
        [ :post, "/telemetry/rankings/tags", { keyword_tag: { tag: "mail", keyword_ids: [ 1 ] } } ],
        [ :delete, "/telemetry/rankings/tags", { keyword_tag: { tag: "mail", keyword_ids: [ 1 ] } } ]
      ],
      search_console: [ [ :patch, "/telemetry/seo/brand_terms", { brand_terms: { terms: "fpd" } } ] ],
      keywords: [
        [ :post, "/telemetry/seo/keyword_research/lookups", { seed: "visiting" } ],
        [ :post, "/telemetry/seo/keyword_research/refreshes", { seed: "visiting" } ]
      ],
      backlinks: [ [ :post, "/telemetry/seo/backlink/syncs", {} ] ],
      alerts: [ [ :post, "/telemetry/seo/alert/runs", {} ] ],
      ai_visibility: [ [ :post, "/telemetry/seo/ai_visibility/runs", {} ] ]
    }.each do |feature, requests|
      requests.each do |verb, path, params|
        it "sends #{verb} #{path} back with a reason and does nothing without #{feature}" do
          uninstall_ahoy_dashboard(feature)

          expect { public_send(verb, path, params: params) }.not_to have_enqueued_job

          expect(response).to have_http_status(:redirect)
          expect(flash[:alert]).to eq("#{AhoyDashboard::FeatureState.for(feature).label} is not installed in this app yet.")
        end
      end
    end

    it "shows the overview with every install step when nothing in the suite is installed" do
      uninstall_every_ahoy_dashboard_feature

      get "/telemetry/seo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(install_command(:search_console))
    end
  end

  describe "the rail" do
    it "lists every page, marking the ones whose feature is missing" do
      uninstall_ahoy_dashboard(:serp)

      read = missing_tables_read(:serp) { get "/telemetry/seo" }

      expect(read).to be_empty
      expect(rail_paths).to contain_exactly("/telemetry/seo", *AhoyDashboard::Seo::Surface::ALL.map(&:path))
      surface_paths(:serp).each { |path| expect(rail_link(path).text.squish).to end_with("Not installed") }
      surface_paths(:search_console).each { |path| expect(rail_link(path).text.squish).not_to include("Not installed") }
    end

    it "lists every page in the section menu too, with the missing ones noted" do
      uninstall_ahoy_dashboard(:backlinks)

      get "/telemetry/rankings"

      menu = document.at_css("nav[aria-label='SEO pages, as a menu']")
      link = menu.css("a").find { |node| node["href"].split("?").first == "/telemetry/seo/backlink" }
      expect(link.text.squish).to include("Backlinks", "Not installed")
    end

    it "marks nothing with everything installed" do
      get "/telemetry/seo"

      expect(rail_paths).to contain_exactly("/telemetry/seo", *AhoyDashboard::Seo::Surface::ALL.map(&:path))
      expect(document.at_css("nav[aria-label='SEO pages']").text).not_to include("Not installed")
    end
  end

  describe "the overview" do
    def step(label)
      document.css("ol li").find { |item| item.text.include?(label) }
    end

    it "keeps the rank tracking steps and section with how to install it" do
      uninstall_ahoy_dashboard(:serp)

      read = missing_tables_read(:serp) { get "/telemetry/seo" }

      expect(read).to be_empty
      expect(response).to have_http_status(:ok)
      [ "Add your site", "Track keywords", "Choose a search provider" ].each do |label|
        expect(step(label).text).to include("Not installed", install_command(:serp))
        expect(step(label).css("a")).to be_empty
      end
      expect(step("Connect Search Console").at_css("a")["href"]).to eq("/telemetry/settings/google_connection")
      expect(document.at_css("section[aria-label='Rank tracking']").text).to include(install_command(:serp))
      expect(response.body).to include("0 of 5 done")
    end

    it "keeps the Search Console step and section with how to install it" do
      uninstall_ahoy_dashboard(:search_console)

      read = missing_tables_read(:search_console) { get "/telemetry/seo" }

      expect(read).to be_empty
      expect(step("Connect Search Console").text).to include("Not installed", install_command(:search_console))
      expect(document.at_css("section[aria-label='Google search']").text).to include(install_command(:search_console))
      expect(step("Add your site").at_css("a")["href"]).to eq("/telemetry/settings/serp_sites/new")
    end

    it "keeps the alerts step with how to install it" do
      uninstall_ahoy_dashboard(:alerts)

      read = missing_tables_read(:alerts) { get "/telemetry/seo" }

      expect(read).to be_empty
      expect(step("Turn on alerts").text).to include("Not installed", install_command(:alerts))
    end

    it "shows no install state with everything installed" do
      get "/telemetry/seo"

      expect(response.body).not_to include("Not installed", "ahoy_dashboard:install")
      expect(step("Add your site").at_css("a")["href"]).to eq("/telemetry/settings/serp_sites/new")
    end
  end

  describe "tracking a query from Search Console without serp" do
    let(:now) { dash_time(2026, 8, 11, 14, 30) }
    let(:reason) { "Rank tracking isn't installed." }

    around { |example| travel_to(now) { example.run } }

    before do
      on = now.to_date - 2
      metrics = { clicks: 10, impressions: 1_000, ctr: 0.01, position: 14.0 }
      AhoyDashboard::SearchConsoleTotal.absorb([ { date: on, device: "", country: "", **metrics } ])
      AhoyDashboard::SearchConsoleKeyword.absorb([ { date: on, query: "visiting hours", device: "", country: "", **metrics } ])
      AhoyDashboard::SearchConsoleRow.absorb([
        { date: on, query: "visiting hours", page: "https://example.com/one", device: "", country: "", **metrics },
        { date: on, query: "visiting hours", page: "https://example.com/two", device: "", country: "", **metrics }
      ])
    end

    %w[/telemetry/search_console_report /telemetry/seo/opportunity /telemetry/seo/cannibalization
       /telemetry/seo/brand_split].each do |path|
      it "shows the track controls disabled with the reason on #{path}" do
        uninstall_ahoy_dashboard(:serp)

        read = missing_tables_read(:serp) { get path }

        expect(read).to be_empty
        expect(response).to have_http_status(:ok)
        box = document.css("input[type=checkbox][disabled]").find { |input| input["aria-label"] == "Track visiting hours" }
        expect(box).to be_present
        expect(document.at_css("##{box["aria-describedby"]}").text).to eq(reason)
        disabled_with_reason("Track these", reason)
        expect(document.css("a, form").map { |node| node["href"] || node["action"] }.compact)
          .to all(satisfy { |href| %w[serp_keyword_import serp_keywords/new rank_keyword].none? { |path| href.include?(path) } })
      end
    end

    it "offers working tracking on the same page with serp installed" do
      get "/telemetry/search_console_report"

      box = document.css("input[name='track[]']").find { |input| input["value"] == "visiting hours" }
      expect(box["disabled"]).to be_nil
      expect(document.css("button[disabled]").map { |node| node.text.squish }).not_to include("Track these")
    end

    it "shows the track keyword button disabled with the reason on one keyword" do
      uninstall_ahoy_dashboard(:serp)

      read = missing_tables_read(:serp) { get "/telemetry/search_console_keyword", params: { q: "visiting hours" } }

      expect(read).to be_empty
      expect(response).to have_http_status(:ok)
      disabled_with_reason("Track keyword", reason)
    end
  end

  describe "keyword research without serp or Search Console" do
    it "lists saved ideas with the track link disabled, reading neither" do
      allow(AhoyDashboard::Keywords).to receive(:enabled?).and_return(true)
      create(:dash_keyword_idea, seed: "visiting", query: "visiting hours", location: "us", language: "en",
             volume: 100, provider: "fake", fetched_at: 1.day.ago)
      uninstall_ahoy_dashboard(:serp, :search_console)

      read = missing_tables_read(:serp, :search_console) do
        get "/telemetry/seo/keyword_research", params: { seed: "visiting", location: "us", language: "en" }
      end

      expect(read).to be_empty
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("visiting hours")
      disabled_with_reason("Track", "Rank tracking isn't installed.")
    end
  end

  describe "visibility without Search Console" do
    it "offers both weightings while Search Console is installed" do
      check = create(:dash_serp_check)

      get "/telemetry/seo/visibility", params: { site: check.site_id }

      expect(document.css("a").map { |link| link.text.squish }).to include("Even", "By impressions")
    end

    it "shows the impressions weighting disabled with the reason" do
      check = create(:dash_serp_check)
      uninstall_ahoy_dashboard(:search_console)

      read = missing_tables_read(:search_console) do
        get "/telemetry/seo/visibility", params: { site: check.site_id, weighting: "impressions" }
      end

      expect(read).to be_empty
      expect(response).to have_http_status(:ok)
      expect(document.css("a").map { |link| link.text.squish }).not_to include("By impressions")
      disabled_with_reason("By impressions", "Search Console isn't installed.")
    end
  end

  describe "alerts switched off" do
    it "keeps the tiles and the recent alerts list, saying why nothing fires" do
      get "/telemetry/seo/alert"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Turn on alerts to get started", "Recent alerts", "Quiet rules")
      expect(document.css("a").find { |link| link.text.squish == "Switch on alerts" }["href"])
        .to eq("/telemetry/settings/features#feature-alerts")
      disabled_with_reason("Check now", "Alerts are off. Turn them on under Settings, Features.")
    end
  end
end
