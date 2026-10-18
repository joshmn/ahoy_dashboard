# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Dashboards::SnapshotEnqueueService do
  let(:snapshots) { AhoyDashboard::Dashboards }
  let(:key) { "snapshot-#{SecureRandom.hex(8)}" }

  include_context "with a test snapshot queue"

  around { |example| travel_to(Time.utc(2026, 8, 11, 14, 30)) { example.run } }

  before { precompute_dashboard! }

  it "enqueues only one refresh while its lease is outstanding" do
    2.times { described_class.call(expected_key: key) }

    expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs.length).to eq(1)
  end

  it "retries a refresh lost by a queue after the bounded lease expires" do
    described_class.call(expected_key: key)
    travel(described_class::LEASE + 1.second)
    described_class.call(expected_key: key)

    expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs.length).to eq(2)
  end

  it "does not let an old worker remove a newer worker's lease" do
    first = described_class.call(expected_key: key)
    travel(described_class::LEASE + 1.second)
    second = described_class.call(expected_key: key)
    described_class.release(expected_key: key, token: first.arguments.last)

    expect(snapshots::SnapshotStore.read_value(key: "#{key}/refresh")).to eq(second.arguments.last)
  end

  it "clears an owned lease when a queued identity is no longer applicable" do
    job = described_class.call(expected_key: key)
    snapshots::SnapshotRefreshJob.perform_now(*job.arguments)

    expect(snapshots::SnapshotStore.read_value(key: "#{key}/refresh")).to be_nil
  end

  it "does not turn stale hits into synchronous refreshes with InlineAdapter" do
    snapshots::SnapshotRefreshJob.queue_adapter = :inline

    expect(described_class.call(expected_key: key)).to be_nil
  end

  it "derives the default dashboard identity when settings enqueue its first preparation" do
    expected = default_snapshot_key

    expect(described_class.call.arguments.first).to eq(expected)
  end

  it "does not read traffic aggregates while enqueueing from settings" do
    expect(captured_sql(/\b(?:FROM|JOIN)\s+"?ahoy_(?:visits|events)"?\b/i, cached: true) { described_class.call }).to be_empty
  end

  it "does not prepare an unfiltered snapshot when a default segment is active" do
    create(:dash_segment, applied_by_default: true,
      filters: [{"dimension" => "country", "operator" => "is", "value" => "CA"}])
    described_class.call

    expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs).to be_empty
  end

  it "does not enqueue while the saved setting is disabled" do
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: false)
    described_class.call

    expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs).to be_empty
  end

  it "discards queued preparation after the saved setting is disabled" do
    job = described_class.call
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: false)
    snapshots::SnapshotRefreshJob.perform_now(*job.arguments)

    expect(snapshots::SnapshotStore.read(key: job.arguments.first)).to be_nil
  end

  it "leaves the entry retryable if the queue rejects a refresh" do
    stub_const("SnapshotFailingQueueAdapter", Class.new do
      def enqueue(_job)
        raise IOError, "queue unavailable"
      end
      def enqueue_at(job, _time)
        enqueue(job)
      end
    end)
    snapshots::SnapshotRefreshJob.queue_adapter = SnapshotFailingQueueAdapter.new
    described_class.call(expected_key: key)
    snapshots::SnapshotRefreshJob.queue_adapter = :test

    expect(described_class.call(expected_key: key)).to be_a(snapshots::SnapshotRefreshJob)
  end

  context "with a configured cache" do
    around do |example|
      previous_store = AhoyDashboard.config.cache_store
      AhoyDashboard.config.cache_store = :memory_store
      example.run
    ensure
      AhoyDashboard.config.cache_store = previous_store
    end

    it "deduplicates refreshes even when the host has no cache" do
      Rails.cache = ActiveSupport::Cache::NullStore.new
      2.times { described_class.call(expected_key: key) }

      expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs.length).to eq(1)
    end

    it "skips refreshes when the selected store cannot retain snapshots" do
      AhoyDashboard.config.cache_store = :null_store
      described_class.call(expected_key: key)

      expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs).to be_empty
    end

    it "releases the configured lease after a job finishes" do
      job = described_class.call(expected_key: key)
      snapshots::SnapshotRefreshJob.perform_now(*job.arguments)
      described_class.call(expected_key: key)

      expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs.length).to eq(2)
    end
  end
end
