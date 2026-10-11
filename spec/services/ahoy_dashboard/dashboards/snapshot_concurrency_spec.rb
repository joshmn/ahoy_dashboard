# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Concurrent default dashboard snapshots" do
  self.use_transactional_tests = false

  let(:snapshots) { AhoyDashboard::Dashboards }

  around do |example|
    cache = Rails.cache
    adapter = snapshots::SnapshotRefreshJob.queue_adapter
    setting_key = AhoyDashboard::Preferences.definition(:site, :precomputed_dashboard).key
    previous_setting = AhoyDashboard::Setting.find_by(key: setting_key)
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    snapshots::SnapshotRefreshJob.queue_adapter = :test
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true)
    @journeys = Queue.new
    capture = ->(*args) { @journeys << args.last[:sql] if args.last[:sql].include?("tm_journey") }
    travel_to(Time.utc(2026, 8, 11, 14, 30)) do
      ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { example.run }
    end
  ensure
    Rails.cache = cache
    snapshots::SnapshotRefreshJob.queue_adapter = adapter
    if previous_setting
      AhoyDashboard::Setting.write(setting_key, previous_setting.value)
    else
      AhoyDashboard::Setting.clear(setting_key)
    end
    AhoyDashboard::Preferences.forget
  end

  def concurrently(&operation)
    ready = Queue.new
    start = Queue.new
    threads = Array.new(4) do
      Thread.new do
        AhoyDashboard::Record.connection_pool.with_connection do |connection|
          AhoyDashboard::Current.reset
          ready << connection.raw_connection.backend_pid
          start.pop
          Rails.cache.respond_to?(:with_local_cache) ? Rails.cache.with_local_cache(&operation) : operation.call
        end
      ensure
        AhoyDashboard::Current.reset
      end
    end
    @connections = Array.new(4) { ready.pop }
    4.times { start << true }
    threads.map(&:value)
  ensure
    threads.each(&:join) if threads
  end

  def read
    query = AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"})
    snapshots::SnapshotQuery.call(query: query, cards: true)
  end

  it "builds the cold dashboard once for four separate PostgreSQL connections" do
    readings = concurrently { read }

    expect([@journeys.size, @connections.uniq.length, readings.map(&:computed_at).uniq]).to eq([1, 4, [Time.current]])
  end

  it "rechecks shared storage after waiting on an expired cache miss" do
    read
    travel(snapshots::Snapshot::MAX_AGE + 1.second)
    @journeys = Queue.new
    readings = concurrently { read }

    expect([@journeys.size, readings.map(&:computed_at).uniq]).to eq([1, [Time.current]])
  end

  it "queues one refresh for simultaneous stale hits" do
    read
    travel(31.seconds)
    concurrently { read }

    expect(snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs.length).to eq(1)
  end

  it "releases the transaction lock after a real PostgreSQL failure" do
    key = "failed-snapshot-#{SecureRandom.hex(8)}"
    begin
      snapshots::SnapshotLockService.call(key: key) { AhoyDashboard::Record.connection.select_value("SELECT 1 / 0") }
    rescue ActiveRecord::StatementInvalid
      # The next connection must acquire the same lock after rollback.
    end
    acquired = Thread.new do
      snapshots::SnapshotLockService.call(key: key, wait: false) { true }
    end.value

    expect(acquired).to eq(true)
  end
end
