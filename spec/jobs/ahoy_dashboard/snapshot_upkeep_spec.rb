# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Scheduled dashboard snapshot upkeep" do
  let(:snapshots) { AhoyDashboard::Dashboards }

  include_context "with a test snapshot queue"

  around { |example| travel_to(Time.utc(2026, 8, 11, 14, 30)) { example.run } }

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

  it "does not enqueue snapshots while the setting has its default off value" do
    AhoyDashboard::TickJob.perform_now

    expect(jobs).to be_empty
  end

  context "with precomputation enabled" do
    before { precompute_dashboard! }

    it "queues the current default dashboard without an incoming page request" do
      AhoyDashboard::TickJob.perform_now

      expect(sole_item(jobs).fetch("arguments").first).to eq(default_snapshot_key)
    end

    it "leaves analytical calculation to the worker" do
      traffic_reads = captured_sql(/\b(?:FROM|JOIN)\s+"?ahoy_(?:visits|events)"?\b/i, cached: true) do
        AhoyDashboard::TickJob.perform_now
      end

      expect(traffic_reads).to be_empty
    end

    it "refreshes an idle dashboard on the next minute's tick" do
      AhoyDashboard::TickJob.perform_now
      perform_refresh
      travel(1.minute)
      AhoyDashboard::TickJob.perform_now
      perform_refresh

      expect(snapshots::SnapshotStore.read(key: default_snapshot_key).computed_at).to eq(Time.current)
    end

    it "does not start a self-scheduling chain when its worker finishes" do
      AhoyDashboard::TickJob.perform_now
      perform_refresh

      expect(jobs.size).to eq(1)
    end

    it "rejects the queued identity if the worker runs in a different schema context" do
      AhoyDashboard::TickJob.perform_now
      connection = AhoyDashboard::Record.connection
      original_path = connection.schema_search_path
      connection.schema_search_path = "public, pg_catalog"
      perform_refresh

      expect(snapshots::SnapshotStore.read(key: default_snapshot_key)).to be_nil
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
