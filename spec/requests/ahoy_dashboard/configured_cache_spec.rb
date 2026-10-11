# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard with its own cache", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }
  let(:snapshots) { AhoyDashboard::Dashboards }
  let!(:funnel) { create(:dash_funnel) }

  around do |example|
    previous_store = AhoyDashboard.config.cache_store
    previous_cache = Rails.cache
    previous_fragments = AhoyDashboard::BaseController.cache_store
    previous_caching = AhoyDashboard::BaseController.perform_caching
    previous_adapter = snapshots::SnapshotRefreshJob.queue_adapter
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    AhoyDashboard::BaseController.cache_store = Rails.cache
    AhoyDashboard::BaseController.perform_caching = true
    snapshots::SnapshotRefreshJob.queue_adapter = :test
    Dir.mktmpdir("dashboard-cache") do |directory|
      AhoyDashboard.configure { |config| config.cache_store = :file_store, directory }
      travel_to(now) { example.run }
    end
  ensure
    AhoyDashboard.config.cache_store = previous_store
    Rails.cache = previous_cache
    AhoyDashboard::BaseController.cache_store = previous_fragments
    AhoyDashboard::BaseController.perform_caching = previous_caching
    snapshots::SnapshotRefreshJob.queue_adapter = previous_adapter
    AhoyDashboard::Current.reset
  end

  before do
    sign_in(create(:user, :admin))
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true)
    visit = dash_visit(started_at: now - 1.day)
    dash_page_view(visit, path: "/prepared")
    job = snapshots::SnapshotEnqueueService.call
    snapshots::SnapshotRefreshJob.perform_now(*job.arguments)
  end

  def panels
    get("/telemetry/reports/pages", headers: { "Tm-Frame" => "report_pages" })
    get("/telemetry/funnels/#{funnel.id}", headers: { "Tm-Frame" => "report_funnel_#{funnel.id}" })
  end

  it "serves the job's snapshot from the configured store" do
    get("/telemetry/dashboard/summary", headers: { "Tm-Frame" => "dash_summary" })

    expect(Nokogiri::HTML5(response.body).at_css("#dash-snapshot-freshness")).to be_present
  end

  it "reuses fragments without writing them to the host controller's store" do
    panels
    rendered = []
    capture = lambda do |*args|
      identifier = args.last[:identifier].to_s
      rendered << identifier if identifier.match?(%r{/(reports|funnels)/_card\.html\.erb\z})
    end
    Rails.cache.clear
    ActiveSupport::Notifications.subscribed(capture, "render_partial.action_view") { panels }

    expect(rendered).to be_empty
  end

  it "leaves the host cache unused when rendering the complete dashboard" do
    host_cache_operations = []
    capture = lambda do |*args|
      payload = args.last
      host_cache_operations << payload[:key] if payload[:store] == "ActiveSupport::Cache::MemoryStore"
    end
    ActiveSupport::Notifications.subscribed(capture, /cache_(read|write|delete|exist)/) do
      get("/telemetry?loading=complete")
    end

    expect(host_cache_operations).to be_empty
  end

  it "still respects disabled fragment caching" do
    AhoyDashboard::BaseController.perform_caching = false
    panels
    rendered = []
    capture = lambda do |*args|
      rendered << args.last[:identifier] if args.last[:identifier].to_s.end_with?("reports/_card.html.erb")
    end
    ActiveSupport::Notifications.subscribed(capture, "render_partial.action_view") { panels }

    expect(rendered.length).to eq(1)
  end
end
