require "rails_helper"

RSpec.describe "Dashboard screens of a feature that is not installed", type: :request do
  def hrefs(selector)
    document.css("#{selector} a[href]").map { |link| link["href"].split("?").first }
  end

  def link(selector, href)
    document.css("#{selector} a[href]").find { |node| node["href"].split("?").first == href }
  end

  def install_command(name)
    "bin/rails generate ahoy_dashboard:install --only #{name}"
  end

  serp_provider = AhoyDashboard::SerpProvider::NAMES.first
  assistant_provider = AhoyDashboard::AssistantProvider::NAMES.first
  ai_assistant = AhoyDashboard::AiVisibility::NAMES.first

  changes = {
    search_console: [
      [ :post, "/telemetry/settings/search_console_sync" ],
      [ :post, "/telemetry/settings/search_console_backfill" ],
      [ :post, "/telemetry/settings/search_console_fill" ],
      [ :patch, "/telemetry/settings/google_credential" ],
      [ :delete, "/telemetry/settings/google_credential/secrets/client_id" ],
      [ :delete, "/telemetry/settings/google_connection" ],
      [ :patch, "/telemetry/settings/search_console_property" ]
    ],
    serp: [
      [ :post, "/telemetry/settings/serp_keywords" ],
      [ :patch, "/telemetry/settings/serp_keywords/1" ],
      [ :delete, "/telemetry/settings/serp_keywords/1" ],
      [ :post, "/telemetry/settings/serp_keywords/1/check" ],
      [ :post, "/telemetry/settings/serp_sites" ],
      [ :delete, "/telemetry/settings/serp_sites/1" ],
      [ :post, "/telemetry/settings/serp_keyword_import" ]
    ],
    alerts: [
      [ :patch, "/telemetry/settings/alert_rules/1" ]
    ],
    ai_visibility: [
      [ :patch, "/telemetry/settings/ai_visibility" ],
      [ :patch, "/telemetry/settings/ai_visibility_assistants/#{ai_assistant}" ],
      [ :delete, "/telemetry/settings/ai_visibility_assistants/#{ai_assistant}/secrets/api_key" ]
    ],
    assistant: [
      [ :patch, "/telemetry/settings/assistant_providers/#{assistant_provider}" ],
      [ :delete, "/telemetry/settings/assistant_providers/#{assistant_provider}/secrets/api_key" ],
      [ :patch, "/telemetry/settings/assistant_dimensions" ],
      [ :post, "/telemetry/chats" ],
      [ :delete, "/telemetry/chats/1" ],
      [ :post, "/telemetry/chats/1/messages" ],
      [ :post, "/telemetry/ask" ]
    ]
  }.freeze

  pages = {
    search_console: %w[/telemetry/settings/google_callback],
    assistant: %w[/telemetry/chats/1]
  }.freeze

  provider_changes = [
    [ :patch, "/telemetry/settings/serp_providers/#{serp_provider}" ],
    [ :delete, "/telemetry/settings/serp_providers/#{serp_provider}/secrets/api_key" ]
  ].freeze

  before { sign_in create(:user, :admin) }

  changes.each do |feature, requests|
    it "refuses every change to #{feature} once it is not installed, and says why" do
      uninstall_ahoy_dashboard(feature)

      wrong = requests.map do |verb, path|
        public_send(verb, path, headers: { "HTTP_REFERER" => "/telemetry/settings/goals" })
        label = AhoyDashboard::FeatureState.for(feature).label
        "#{verb} #{path} answered #{response.status}" unless response.redirect? && flash[:alert] == "#{label} is not installed in this app yet."
      end.compact

      expect(wrong).to be_empty
    end
  end

  pages.each do |feature, paths|
    it "shows how to install #{feature} on its pages instead of the page" do
      uninstall_ahoy_dashboard(feature)

      wrong = paths.map do |path|
        get path
        "#{path} answered #{response.status}" unless response.ok? && response.body.include?(install_command(feature))
      end.compact

      expect(wrong).to be_empty
    end
  end

  it "keeps the search provider while any feature that searches through it is installed" do
    uninstall_ahoy_dashboard(:serp, :keywords)

    get "/telemetry/settings/serp_providers"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(install_command(:backlinks))
  end

  it "shows how to install the search provider once nothing that searches through it is installed" do
    uninstall_ahoy_dashboard(:serp, :keywords, :backlinks)

    get "/telemetry/settings/serp_providers"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(install_command(:serp), install_command(:keywords), install_command(:backlinks))

    provider_changes.each do |verb, path|
      public_send(verb, path)
      expect(response).to be_redirect
    end
  end

  describe "the settings nav" do
    it "lists every section without a not installed mark when everything is installed" do
      get "/telemetry/settings/goals"
      nav = document.at_css("nav[aria-label='AhoyDashboard sections']")

      expect(hrefs("nav[aria-label='AhoyDashboard sections']"))
        .to eq(AhoyDashboard::SettingsSection::ALL.map(&:path))
      expect(nav.text).not_to include(AhoyDashboard::FeatureState::BADGE)
    end

    it "keeps every section, and marks the ones that are not installed" do
      uninstall_ahoy_dashboard(:search_console, :alerts, :ai_visibility, :assistant, :serp)

      get "/telemetry/settings/goals"

      expect(hrefs("nav[aria-label='AhoyDashboard sections']"))
        .to eq(AhoyDashboard::SettingsSection::ALL.map(&:path))
      expect(hrefs("#tm-set-section-menu")).to match_array(AhoyDashboard::SettingsSection::ALL.map(&:path))

      marked = %w[google_connection alert_rules ai_visibility/edit assistant_providers serp_keywords]
      marked.each do |path|
        expect(link("nav[aria-label='AhoyDashboard sections']", "/telemetry/settings/#{path}").text)
          .to include(AhoyDashboard::FeatureState::BADGE)
        expect(link("#tm-set-section-menu", "/telemetry/settings/#{path}").text)
          .to include(AhoyDashboard::FeatureState::BADGE)
      end
      %w[goals serp_providers job_runs].each do |path|
        expect(link("nav[aria-label='AhoyDashboard sections']", "/telemetry/settings/#{path}").text)
          .not_to include(AhoyDashboard::FeatureState::BADGE)
      end
    end
  end

  describe "the command palette" do
    it "offers everything, and marks what is not installed" do
      uninstall_ahoy_dashboard(:search_console, :serp, :assistant)

      get "/telemetry/palette"
      surfaces = AhoyDashboard::Seo::Surface::ALL.map { |surface| surface.path.split("?").first }

      expect(hrefs("nav[aria-label='Dashboard commands']")).to include("/telemetry/chats", "/telemetry/seo", *surfaces,
                                                   *AhoyDashboard::SettingsSection::ALL.map(&:path))
      %w[/telemetry/chats /telemetry/settings/google_connection /telemetry/settings/serp_keywords
         /telemetry/rankings /telemetry/seo/opportunity].each do |path|
        expect(link("nav[aria-label='Dashboard commands']", path).text).to include(AhoyDashboard::FeatureState::BADGE)
      end
      %w[/telemetry/seo /telemetry/seo/backlink /telemetry/settings/alert_rules].each do |path|
        expect(link("nav[aria-label='Dashboard commands']", path).text).not_to include(AhoyDashboard::FeatureState::BADGE)
      end
    end

    it "marks nothing while everything is installed" do
      get "/telemetry/palette"

      expect(document.at_css("nav[aria-label='Dashboard commands']").text).not_to include(AhoyDashboard::FeatureState::BADGE)
    end

    it "marks SEO when no SEO feature is installed" do
      uninstall_ahoy_dashboard(:search_console, :serp, :keywords, :backlinks, :alerts, :ai_visibility)

      get "/telemetry/palette"

      expect(link("nav[aria-label='Dashboard commands']", "/telemetry/seo").text).to include(AhoyDashboard::FeatureState::BADGE)
    end
  end

  describe "the header" do
    it "keeps the SEO tab when no SEO feature is installed" do
      uninstall_ahoy_dashboard(:search_console, :serp, :keywords, :backlinks, :alerts, :ai_visibility)

      get "/telemetry"

      expect(response).to have_http_status(:ok)
      expect(hrefs("nav[aria-label='Primary']")).to eq([ "/telemetry/", "/telemetry/explore", "/telemetry/seo" ])
    end

    it "keeps Ask, shows how to install it in the panel, and never looks the remembered chat up" do
      uninstall_ahoy_dashboard(:assistant)
      cookies[AhoyDashboard::BaseController::ASK_COOKIE] =
        AhoyDashboard::Assistant::PanelMemory.new(open: true, chat_id: 1).to_s

      get "/telemetry/explore"
      panel = document.at_css("#dash-ask")

      expect(response).to have_http_status(:ok)
      expect(document.at_css("[aria-controls='dash-ask']")["href"]).to start_with("/telemetry/ask")
      expect(panel.text).to include(install_command(:assistant))
      expect(document.at_css("html")["data-ask"]).to eq("shut")
    end

    it "answers the panel's own frame with how to install it" do
      uninstall_ahoy_dashboard(:assistant)

      get_frame("/telemetry/ask", AhoyDashboard::AsksController::FRAME)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(install_command(:assistant))
    end

    it "lets the panel close without an alert waiting on the next page" do
      uninstall_ahoy_dashboard(:assistant)

      delete "/telemetry/ask"

      expect(response).to have_http_status(:no_content)
      expect(flash[:alert]).to be_nil
    end
  end

  describe "the dashboard" do
    it "keeps the Search Console card, which shows how to install it" do
      uninstall_ahoy_dashboard(:search_console)

      get "/telemetry"

      expect(document.css("[src^='/telemetry/search_console']")).to be_present

      get_frame("/telemetry/search_console", AhoyDashboard::SearchConsolePresenter::FRAME)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(install_command(:search_console))
      expect(document.at_css("##{AhoyDashboard::SearchConsolePresenter::FRAME}").text).to include("Not installed yet")
    end
  end

  describe "alert rules" do
    let(:rank_rules) { AhoyDashboard::Alerts::Catalogue.all.select { |definition| definition.group == :rank } }

    before { AhoyDashboard::Alerts::Rules::InstallCommand.call }

    it "lists every rule, and marks the ones whose source is not installed" do
      uninstall_ahoy_dashboard(:serp)

      get "/telemetry/settings/alert_rules"
      body = document.at_css("main")

      expect(response).to have_http_status(:ok)
      expect(body.text).to include(*AhoyDashboard::Alerts::Catalogue.all.map(&:name))

      rank_rules.each do |definition|
        row = body.css("tr").find { |node| node.text.include?(definition.name) }

        expect(row.text).to include("Needs Rank tracking, which isn't installed.", AhoyDashboard::FeatureState::BADGE)
        expect(row.css("a[href]").map { |node| node["href"] }).to include(%r{/telemetry/settings/alert_rules/\d+/edit})
      end
    end

    it "shows a waiting rule's form with its status locked and how to install what it needs" do
      uninstall_ahoy_dashboard(:serp)
      get "/telemetry/settings/alert_rules"
      rule = AhoyDashboard::AlertRule.find_by!(key: rank_rules.first.key)

      get "/telemetry/settings/alert_rules/#{rule.id}/edit"
      status = document.at_css("select[name='alert_rule[enabled]']")

      expect(response).to have_http_status(:ok)
      expect(status["disabled"]).not_to be_nil
      expect(response.body).to include(install_command(:serp))
      expect(document.at_css("main").text).to include("Needs Rank tracking, which isn't installed.")
    end

    it "refuses to switch on a rule whose source is not installed" do
      uninstall_ahoy_dashboard(:serp)
      get "/telemetry/settings/alert_rules"
      rule = AhoyDashboard::AlertRule.find_by!(key: rank_rules.first.key)

      patch "/telemetry/settings/alert_rules/#{rule.id}", params: { alert_rule: { enabled: true } }

      expect(response).to redirect_to("/telemetry/settings/alert_rules/#{rule.id}/edit")
      expect(rule.reload.enabled).to be(false)
    end
  end

  describe "the jobs screen" do
    it "says a job is not installed and how to install it" do
      uninstall_ahoy_dashboard(:places)

      get "/telemetry/settings/job_runs"
      row = document.css("tr").find { |node| node.at_css("a[href='/telemetry/settings/job_runs/places']") }

      expect(row.text).to include(AhoyDashboard::FeatureState::BADGE, install_command(:places))
      expect(row.at_css("button[disabled]")).to be_present

      get "/telemetry/settings/job_runs/places"

      expect(document.at_css("main").text).to include("Place list is not installed.", install_command(:places))
    end
  end

  describe "the missing tables notice" do
    it "names each switched-on feature with no tables, on settings pages too" do
      uninstall_ahoy_dashboard(:serp, :alerts)
      switch_on_ahoy_dashboard(:serp, :alerts)

      %w[/telemetry /telemetry/settings/goals].each do |path|
        get path
        notices = document.css("main [role=alert], main [role=status]").map { |node| node.text.squish }

        expect(response).to have_http_status(:ok), path
        expect(notices).to include(AhoyDashboard::Installation.fetch(:serp).missing_message,
                                   AhoyDashboard::Installation.fetch(:alerts).missing_message), path
      end
    end

    it "says nothing about a feature that is switched off" do
      uninstall_ahoy_dashboard(:serp)

      get "/telemetry"

      expect(response.body).not_to include(AhoyDashboard::Installation.fetch(:serp).missing_message)
    end

    it "says nothing when everything is installed" do
      switch_on_ahoy_dashboard(:serp)

      get "/telemetry"

      expect(response.body).not_to include("its tables are not installed")
    end
  end

  describe "rank tracking without its neighbours" do
    it "points the import screen at installing Search Console when it is not installed" do
      uninstall_ahoy_dashboard(:search_console)

      get "/telemetry/settings/serp_keyword_import/new"

      expect(response).to have_http_status(:ok)
      expect(document.css("main a[href='/telemetry/settings/google_connection']").map { |node| node.text.squish })
        .to include("Install Search Console")
      expect(document.at_css("textarea[name='serp_keyword_import[pasted]']")).to be_present
    end

    it "draws the keyword list and its spend without alerts installed" do
      uninstall_ahoy_dashboard(:alerts)

      get "/telemetry/settings/serp_keywords"

      expect(response).to have_http_status(:ok)
    end

    it "says why there is no place picker when the place list is not installed" do
      uninstall_ahoy_dashboard(:places, :search_console)

      get "/telemetry/settings/serp_keywords/new"

      expect(response).to have_http_status(:ok)
      expect(document.at_css("[data-dash--place-picker-url-value]")).to be_nil
      expect(link("main", "/telemetry/settings/job_runs/places").text.squish)
        .to eq("The place list is not installed, so places are typed in for now.")
    end
  end

  describe "Ask while the assistant is switched off" do
    before { allow(AhoyDashboard::Assistant).to receive(:available?).and_return(false) }

    it "keeps the question box on a conversation, disabled, with the reason" do
      chat = create(:dash_chat)

      get "/telemetry/chats/#{chat.id}"
      box = document.at_css("textarea[name='message[content]']")
      send = document.at_css("button[aria-label='Ask']")

      expect(box["disabled"]).not_to be_nil
      expect(send["disabled"]).not_to be_nil
      expect(document.at_css("##{send['aria-describedby']}").text.squish)
        .to eq(AhoyDashboard::Settings::Display.assistant_notice)
    end

    it "keeps the panel's question box and suggestions, disabled" do
      get_frame("/telemetry/ask", AhoyDashboard::AsksController::FRAME)

      expect(document.at_css("textarea#ask_content")["disabled"]).not_to be_nil
      expect(document.at_css("button[aria-label='Ask']")["disabled"]).not_to be_nil
    end
  end
end
