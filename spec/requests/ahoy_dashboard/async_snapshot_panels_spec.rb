# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Prepared asynchronous dashboard panels", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }
  let!(:funnel) { create(:dash_funnel) }
  let!(:question) { create(:dash_saved_query, pinned: true) }

  around do |example|
    previous_cache = Rails.cache
    previous_fragments = AhoyDashboard::BaseController.cache_store
    previous_caching = AhoyDashboard::BaseController.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    AhoyDashboard::BaseController.cache_store = Rails.cache
    AhoyDashboard::BaseController.perform_caching = true
    travel_to(now) { example.run }
  ensure
    Rails.cache = previous_cache
    AhoyDashboard::BaseController.cache_store = previous_fragments
    AhoyDashboard::BaseController.perform_caching = previous_caching
    AhoyDashboard::Current.reset
  end

  before do
    sign_in(create(:user, :admin))
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true)
    visit = dash_visit(started_at: now - 1.day, visitor: "prepared")
    dash_page_view(visit, path: "/prepared")
    AhoyDashboard::Dashboards::SnapshotRefreshService.call(force: true)
  end

  def frame(path, id)
    get "/telemetry/#{path}", headers: { "Tm-Frame" => id }
  end

  def aggregate_statements
    found = []
    capture = lambda do |*args|
      sql = args.last[:sql]
      found << sql if sql.match?(/tm_visits|tm_journey|GROUP BY|COUNT\(DISTINCT/i)
    end
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { yield }
    found
  end

  {
    "reports/pages" => "report_pages", "pinned_questions" => "dash_pinned_questions",
    "journey" => "dash_journey", "goal_conversions" => "dash_goal_conversions",
    "search_console" => "report_search_console"
  }.each do |path, id|
    it "uses the prepared #{path} slice without repeating analytical aggregates" do
      found = aggregate_statements { frame(path, id) }

      expect([response.status, found]).to eq([200, []])
    end
  end

  it "uses the prepared funnel slice without repeating analytical aggregates" do
    found = aggregate_statements { frame("funnels/#{funnel.id}", AhoyDashboard::FunnelPresenter.frame_id(funnel)) }

    expect([response.status, found]).to eq([200, []])
  end

  it "uses report and funnel HTML fragments on later requests for the same generation" do
    frame("reports/pages", "report_pages")
    frame("funnels/#{funnel.id}", AhoyDashboard::FunnelPresenter.frame_id(funnel))
    rendered = []
    capture = lambda do |*args|
      identifier = args.last[:identifier].to_s
      rendered << identifier if identifier.match?(%r{/(reports|funnels)/_card\.html\.erb\z})
    end
    ActiveSupport::Notifications.subscribed(capture, "render_partial.action_view") do
      frame("reports/pages", "report_pages")
      frame("funnels/#{funnel.id}", AhoyDashboard::FunnelPresenter.frame_id(funnel))
    end

    expect(rendered).to be_empty
  end

  it "shows refreshed rows after a new snapshot generation" do
    frame("reports/pages", "report_pages")
    travel(31.seconds)
    visit = dash_visit(started_at: Time.current, visitor: "updated")
    dash_page_view(visit, path: "/updated")
    AhoyDashboard::Dashboards::SnapshotRefreshService.call(force: true)
    frame("reports/pages", "report_pages")

    expect(Nokogiri::HTML5(response.body).at_css("#report_pages").text).to include("/updated")
  end
end
