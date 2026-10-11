# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Scheduled dashboard snapshot upkeep" do
  let(:snapshots) { AhoyDashboard::Dashboards }

  around do |example|
    cache = Rails.cache
    adapter = snapshots::SnapshotRefreshJob.queue_adapter
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    snapshots::SnapshotRefreshJob.queue_adapter = :test
    travel_to(Time.utc(2026, 8, 11, 14, 30)) { example.run }
  ensure
    Rails.cache = cache
    snapshots::SnapshotRefreshJob.queue_adapter = adapter
  end

  before { AhoyDashboard::Features.names.each { |name| AhoyDashboard::Features.switch(name, false) } }

  def jobs
    snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs.select do |job|
      job[:job] == snapshots::SnapshotRefreshJob
    end
  end

  def perform_refresh
    job = ActiveJob::Base.deserialize(jobs.last)
    job.perform_now
  end

  def key
    query = AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"})
    snapshots::SnapshotKeyQuery.call(query: query)
  end

  it "does not enqueue snapshots while the setting has its default off value" do
    AhoyDashboard::TickJob.perform_now

    expect(jobs).to be_empty
  end

  context "with precomputation enabled" do
    before { AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true) }

    it "queues the current default dashboard without an incoming page request" do
      AhoyDashboard::TickJob.perform_now

      expect(sole_item(jobs).fetch("arguments").first).to eq(key)
    end

    it "leaves analytical calculation to the worker" do
      traffic_reads = []
      capture = lambda do |*args|
        sql = args.last[:sql]
        traffic_reads << sql if sql.match?(/\b(?:FROM|JOIN)\s+"?ahoy_(?:visits|events)"?\b/i)
      end

      ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { AhoyDashboard::TickJob.perform_now }

      expect(traffic_reads).to be_empty
    end

    it "shares the outstanding refresh lease across repeated ticks" do
      2.times { AhoyDashboard::TickJob.perform_now }

      expect(jobs.size).to eq(1)
    end

    it "refreshes an idle dashboard on the next minute's tick" do
      AhoyDashboard::TickJob.perform_now
      perform_refresh
      travel(1.minute)
      AhoyDashboard::TickJob.perform_now
      perform_refresh

      expect(snapshots::SnapshotStore.read(key: key).computed_at).to eq(Time.current)
    end

    it "keeps the original timestamp when another request has already built a fresh snapshot" do
      original = snapshots::SnapshotRefreshService.call
      travel(20.seconds)
      AhoyDashboard::TickJob.perform_now
      perform_refresh

      expect(snapshots::SnapshotStore.read(key: key).computed_at).to eq(original.computed_at)
    end

    it "does not start a self-scheduling chain when its worker finishes" do
      AhoyDashboard::TickJob.perform_now
      perform_refresh

      expect(jobs.size).to eq(1)
    end

    it "does not enqueue an unfiltered dashboard when a default segment is configured" do
      create(:dash_segment, applied_by_default: true,
        filters: [{"dimension" => "country", "operator" => "is", "value" => "CA"}])
      AhoyDashboard::TickJob.perform_now

      expect(jobs).to be_empty
    end

    it "discards a queued tick refresh after precomputation is disabled" do
      AhoyDashboard::TickJob.perform_now
      AhoyDashboard::Preferences.write(:site, precomputed_dashboard: false)
      perform_refresh

      expect(snapshots::SnapshotStore.read(key: key)).to be_nil
    end

    it "rejects the queued identity if the worker runs in a different schema context" do
      AhoyDashboard::TickJob.perform_now
      connection = AhoyDashboard::Record.connection
      original_path = connection.schema_search_path
      connection.schema_search_path = "public, pg_catalog"
      perform_refresh

      expect(snapshots::SnapshotStore.read(key: key)).to be_nil
    ensure
      connection.schema_search_path = original_path if connection
    end

    it "keeps other features on their own cadence when the tick runs every minute" do
      AhoyDashboard::Features.switch(:serp, true)
      AhoyDashboard::TickJob.perform_now
      travel(1.minute)
      AhoyDashboard::TickJob.perform_now

      expect(AhoyDashboard::Serp::DispatchJob.queue_adapter.enqueued_jobs.count { |job| job[:job] == AhoyDashboard::Serp::DispatchJob })
        .to eq(1)
    end
  end
end
