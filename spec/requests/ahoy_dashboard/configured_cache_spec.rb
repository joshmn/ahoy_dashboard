# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard with its own cache", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }
  let(:snapshots) { AhoyDashboard::Dashboards }
  let!(:funnel) { create(:dash_funnel) }

  include_context "with fragment caching"

  around do |example|
    previous_store = AhoyDashboard.config.cache_store
    previous_adapter = snapshots::SnapshotRefreshJob.queue_adapter
    snapshots::SnapshotRefreshJob.queue_adapter = :test
    Dir.mktmpdir("dashboard-cache") do |directory|
      AhoyDashboard.configure { |config| config.cache_store = :file_store, directory }
      travel_to(now) { example.run }
    end
  ensure
    AhoyDashboard.config.cache_store = previous_store
    snapshots::SnapshotRefreshJob.queue_adapter = previous_adapter
  end

  before do
    sign_in(create(:user, :admin))
    precompute_dashboard!
    dash_landing("/prepared", at: now - 1.day)
    job = snapshots::SnapshotEnqueueService.call
    snapshots::SnapshotRefreshJob.perform_now(*job.arguments)
  end

  def panels
    get_frame("/telemetry/reports/pages", "report_pages")
    get_frame("/telemetry/funnels/#{funnel.id}", "report_funnel_#{funnel.id}")
  end

  it "serves the job's snapshot from the configured store" do
    get_frame("/telemetry/dashboard/summary", "dash_summary")

    expect(document.at_css("#dash-snapshot-freshness")).to be_present
  end

  it "reuses fragments without writing them to the host controller's store" do
    panels
    Rails.cache.clear
    rendered = rendered_card_partials { panels }

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
    rendered = rendered_card_partials(%r{reports/_card\.html\.erb\z}) { panels }

    expect(rendered.length).to eq(1)
  end
end
