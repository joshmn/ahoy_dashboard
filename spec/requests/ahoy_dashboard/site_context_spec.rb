# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard site context", type: :request do
  include_context "with dashboard sites"
  include_context "with a memory cache"

  around do |example|
    options = AhoyDashboard.config.url_options
    AhoyDashboard.config.url_options = -> { { site_id: AhoyDashboard::Context.current } }
    Rails.application.routes.draw do
      devise_for :users, only: :sessions
      mount AhoyDashboard::Engine, at: "/sites/:site_id/analytics"
    end
    example.run
  ensure
    AhoyDashboard.config.url_options = options
    Rails.application.reload_routes!
  end

  before do
    sign_in(create(:user, :admin))
    %w[first second].each do |site|
      within_site(site) do
        AhoyDashboard::Preferences.write(:site, host: "same.example.com")
        visit = dash_visit(id: 42, started_at: 1.hour.ago, visitor: "same-visitor", referring_domain: "#{site}.example.com")
        dash_page_view(visit, path: "/#{site}")
        AhoyDashboard::Goal.create!(id: 42, event_name: site, position: 0)
      end
    end
  end

  it "keeps presenter links inside the selected mount" do
    get "/sites/first/analytics"

    links = document.css('a[href^="/"]').map { |link| link["href"] }
    expect(links).to all(start_with("/sites/first/analytics"))
  end

  it "keeps controller redirects inside the selected mount" do
    delete "/sites/second/analytics/view"

    expect(response).to redirect_to("/sites/second/analytics/")
  end

  it "keeps background URL helpers inside the selected mount" do
    path = within_site("second") { AhoyDashboard.routes.settings_google_callback_url(host: "analytics.example.com") }

    expect(path).to eq("http://analytics.example.com/sites/second/analytics/settings/google_callback")
  end

  it "reads only the selected site's definitions" do
    get "/sites/first/analytics/settings/goals"
    get "/sites/second/analytics/settings/goals"

    expect(document.css("tbody").text.scan(/\b(?:first|second)\b/).uniq).to eq([ "second" ])
  end

  it "streams only the selected site's page data after the controller returns" do
    get "/sites/first/analytics/exports/pages.csv", params: { period: "7d" }

    expect(response.body.scan(%r{/(?:first|second)}).uniq).to eq([ "/first" ])
  end

  it "streams assistant replies from the selected site" do
    %w[first second].each do |site|
      within_site(site) do
        chat = create(:dash_chat, id: 42)
        create(:dash_chat_message, :assistant, chat: chat, content: "Answer for #{site}")
      end
    end

    get "/sites/second/analytics/chats/42/stream"

    expect(response.body).to include("Answer for second")
    expect(response.body).not_to include("Answer for first")
  end

  it "isolates referrer allowlists even when hosts and visitor tokens match" do
    within_site("first") { AhoyDashboard::FaviconService.known_domains }

    expect(within_site("second") { AhoyDashboard::FaviconService.known_domains }).to eq(Set["second.example.com"])
  end

  it "clears memoized settings across nested context switches" do
    within_site("first") { AhoyDashboard::Preferences.write(:site, host: "first.example.com") }
    host = within_site("second") do
      AhoyDashboard.host
      within_site("first") { AhoyDashboard.host }
      AhoyDashboard.host
    end

    expect(host).to eq("same.example.com")
  end

  it "isolates settings changes made using an overlapping record ID" do
    patch "/sites/second/analytics/settings/goals/42", params: { goal: { kind: "custom_event", event_name: "changed" } }

    expect(response).to redirect_to("/sites/second/analytics/settings/goals")
    expect(within_site("second") { AhoyDashboard::Goal.find(42).event_name }).to eq("changed")
    expect(within_site("first") { AhoyDashboard::Goal.find(42).event_name }).to eq("first")
  end

  it "keeps remembered views separate when switching sites" do
    get "/sites/first/analytics", params: { period: "7d" }
    get "/sites/second/analytics", params: { period: "30d" }
    get "/sites/first/analytics"

    expect(document.at_css("#tm-period-button").text.strip).to eq("Last 7 days")
  end

  context "with Google authorization" do
    before do
      AhoyDashboard.config.url_options = -> do
        { site_id: AhoyDashboard::Context.current, host: "analytics.example.com", protocol: "https" }
      end
      %w[first second].each do |site|
        within_site(site) do
          store_google_client
          AhoyDashboard::Preferences.write(:search_console, enabled: true)
        end
      end
    end

    it "uses the dashboard host for the callback without changing the tracked host" do
      get "/sites/second/analytics/settings/google_authorization/new"
      options = URI.decode_www_form(URI(response.location).query).to_h

      expect(options["redirect_uri"]).to eq("https://analytics.example.com/sites/second/analytics/settings/google_callback")
      expect(within_site("second") { AhoyDashboard.host }).to eq("same.example.com")
    end

    it "keeps simultaneous Google connections in their originating sites" do
      states = %w[first second].map do |site|
        get "/sites/#{site}/analytics/settings/google_authorization/new"
        URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
      end

      %w[first second].zip(states).each do |site, state|
        stub_token(body: token_body("refresh_token" => "token-for-#{site}"))
        get "/sites/#{site}/analytics/settings/google_callback", params: { code: "code", state: state }

        expect(response).to redirect_to("/sites/#{site}/analytics/settings/search_console_property/edit")
        expect(within_site(site) { AhoyDashboard::GoogleAccount.current.refresh_token }).to eq("token-for-#{site}")
      end
    end

    it "refuses a Google callback started for another site" do
      get "/sites/first/analytics/settings/google_authorization/new"
      state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")

      get "/sites/second/analytics/settings/google_callback", params: { code: "code", state: state }

      expect(flash[:alert]).to include("did not come back from a sign-in this browser started")
      expect(a_request(:post, token_url)).not_to have_been_made
      expect(within_site("second") { AhoyDashboard::GoogleAccount.count }).to eq(0)
    end
  end
end
