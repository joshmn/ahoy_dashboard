# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard host integration", type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in(admin) }

  around do |example|
    navigation = AhoyDashboard.config.navigation_partial
    permissions = AhoyDashboard.config.authorize_action
    authorization = AhoyDashboard.config.authorize
    example.run
  ensure
    AhoyDashboard.config.navigation_partial = navigation
    AhoyDashboard.config.authorize_action = permissions
    AhoyDashboard.config.authorize = authorization
  end

  it "runs the configured host controller's callbacks" do
    get "/telemetry"

    expect(response.headers["X-Dashboard-Host"]).to eq("present")
  end

  it "renders navigation supplied by the host" do
    AhoyDashboard.config.navigation_partial = "dashboard_host/navigation"
    get "/telemetry"

    expect(document.at_css('nav[aria-label="Your sites"] a')["href"]).to eq("/sites")
  end

  context "with read access" do
    before { AhoyDashboard.config.authorize_action = ->(_controller, permission) { permission == :read } }

    it "renders reports" do
      AhoyDashboard.config.authorize = ->(controller) { controller.current_user.present? }
      sign_in create(:user)
      get "/telemetry"

      expect(response).to have_http_status(:ok)
    end

    it "allows clearing the reader's remembered view" do
      delete "/telemetry/view"

      expect(response).to redirect_to("/telemetry/")
    end

    it "hides the settings and assistant navigation" do
      get "/telemetry"

      expect(document.css('.hd-right a[title="Settings"], .hd-ask')).to be_empty
    end

    it "keeps setup links and write controls out of reports" do
      paths = %w[
        /telemetry /telemetry/explore /telemetry/funnels /telemetry/search_console_report
        /telemetry/rankings /telemetry/seo /telemetry/seo/conversion /telemetry/seo/keyword_gap
        /telemetry/seo/keyword_research /telemetry/seo/backlink /telemetry/seo/alert
        /telemetry/seo/ai_visibility /telemetry/seo/brand_split
      ]

      aggregate_failures do
        paths.each do |path|
          get path

          expect(response).to have_http_status(:ok), path
          expect(document.css('a[href*="/settings/"]')).to be_empty, path
          writes = document.css('form[method="post"]').reject { |form| form["action"] == "/telemetry/view" }
          expect(writes).to be_empty, path
        end
      end
    end

    it "keeps management and assistant destinations out of the palette" do
      get "/telemetry/palette", headers: { "Tm-Frame" => "tm-palette" }

      expect(document.css('a[href*="/settings/"], a[href*="/chats"]')).to be_empty
    end

    it "refuses every management route before queries or jobs run" do
      routes = AhoyDashboardRequestRoutes.every.select do |route|
        route.controller.start_with?("ahoy_dashboard/settings/") ||
          (!%w[GET HEAD].include?(route.verb) && route.controller != "ahoy_dashboard/views")
      end

      aggregate_failures do
        routes.each do |route|
          sign_in(admin)
          jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size
          statements = captured_sql { public_send(route.verb.downcase, route.path) }.select { |sql| sql.include?("ahoy_") }
          added_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size - jobs
          expect([ response.status, statements, added_jobs ]).to eq([ 404, [], 0 ]), route.to_s
        end
      end
    end

    it "refuses assistant reads" do
      get "/telemetry/chats"

      expect(response).to have_http_status(:not_found)
    end
  end

  it "allows assistant access without granting settings access" do
    AhoyDashboard.config.authorize_action = ->(_controller, permission) { permission != :manage }
    post "/telemetry/chats"

    expect(AhoyDashboard::Chat.count).to eq(1)
  end
end
