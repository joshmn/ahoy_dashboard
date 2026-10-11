# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Dashboards::SnapshotRefreshService do
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

  before { AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true) }

  def key
    snapshots::SnapshotKeyQuery.call(query: AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"}))
  end

  it "does no work while the saved setting is disabled" do
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: false)

    expect(described_class.call).to be_nil
  end

  it "rejects an identity from another schema or configuration" do
    expect(described_class.call(expected_key: "foreign-identity")).to be_nil
  end

  it "reuses a fresh reading without extending its calculation timestamp" do
    original = described_class.call
    travel(20.seconds)

    expect(described_class.call.computed_at).to eq(original.computed_at)
  end

  it "refreshes a stale reading on an explicit prewarm" do
    original = described_class.call
    travel(31.seconds)

    expect(described_class.call.computed_at).to eq(original.computed_at + 31.seconds)
  end

  it "does not publish under an obsolete identity when a definition changes during the build" do
    original_key = key
    changed = false
    capture = lambda do |*args|
      next unless !changed && args.last[:sql].include?("tm_journey")

      changed = true
      AhoyDashboard::Annotation.create!(label: "Concurrent deploy", happened_at: Time.current, kind: "deploy")
    end
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { described_class.call }

    expect(snapshots::SnapshotStore.read(key: original_key)).to be_nil
  end

  it "rejects a queued refresh whose date range has rolled over" do
    yesterday = key
    travel(1.day)

    expect(described_class.call(expected_key: yesterday)).to be_nil
  end

  it "retains numerical readings for at most five minutes including ordinary cache age" do
    snapshot = described_class.call
    travel(5.minutes - AhoyDashboard::ScopeQuery::TOTAL_TTL)

    expect(snapshot.usable?).to eq(false)
  end

  it "recovers a cache entry containing an invalid calculation timestamp" do
    Rails.cache.write(key, {"computed_at" => "invalid", "payload" => {}})

    expect(described_class.call.computed_at).to eq(Time.current)
  end

  it "keeps the previous reading after a failed database refresh" do
    original = described_class.call
    original_key = key
    travel(31.seconds)
    capture = lambda do |*args|
      AhoyDashboard::Record.connection.select_value("SELECT 1 / 0") if args.last[:sql].include?("tm_journey")
    end
    begin
      ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { described_class.call }
    rescue ActiveRecord::StatementInvalid
      # Failed refreshes leave the still-bounded previous cache entry intact.
    end

    expect(snapshots::SnapshotStore.read(key: original_key).computed_at).to eq(original.computed_at)
  end

  it "does not publish an already expired reading after an exceptionally slow build" do
    original_key = key
    moved = false
    capture = lambda do |*args|
      next unless !moved && args.last[:sql].include?("tm_journey")

      moved = true
      travel(snapshots::Snapshot::MAX_AGE)
    end
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { described_class.call }

    expect(snapshots::SnapshotStore.read(key: original_key)).to be_nil
  end
end
