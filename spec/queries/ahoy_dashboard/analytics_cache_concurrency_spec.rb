# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Concurrent analytical cache fills" do
  self.use_transactional_tests = false

  let(:key) { "concurrent-#{SecureRandom.hex(8)}" }
  let(:query) { "SELECT count(*) FROM generate_series(1, 3), pg_sleep(0.05) /* dashboard_cache_probe */" }

  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @fills = Queue.new
    capture = ->(*args) { @fills << args.last[:sql] if args.last[:sql].include?("dashboard_cache_probe") }
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { example.run }
  ensure
    Rails.cache = previous
  end

  def concurrently(paths: Array.new(4, ActiveRecord::Base.connection.schema_search_path), sql: query)
    ready = Queue.new
    start = Queue.new
    threads = paths.map do |path|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          previous = connection.schema_search_path
          begin
            connection.schema_search_path = path
            ready << connection.raw_connection.backend_pid
            start.pop
            fill = -> { AhoyDashboard::AnalyticsCache.fetch(key: key, connection: connection) { connection.select_value(sql) } }
            Rails.cache.respond_to?(:with_local_cache) ? Rails.cache.with_local_cache(&fill) : fill.call
          ensure
            connection.schema_search_path = previous
          end
        end
      end
    end
    @connections = paths.map { ready.pop }
    paths.each { start << true }
    threads.map(&:value)
  ensure
    threads.each(&:join) if threads
  end

  it "fills a cold entry once across four real database connections" do
    values = concurrently

    expect([@fills.size, @connections.uniq.length, values]).to eq([1, 4, [3, 3, 3, 3]])
  end

  it "fills an expired entry once and gives every waiter the fresh result" do
    connection = ActiveRecord::Base.connection
    AhoyDashboard::AnalyticsCache.fetch(key: key, connection: connection) { 0 }
    travel(AhoyDashboard::ScopeQuery::TOTAL_TTL + 1.second)
    values = concurrently

    expect([@fills.size, values]).to eq([1, [3, 3, 3, 3]])
  end

  it "keeps simultaneous fills isolated by the connection search path" do
    values = concurrently(paths: %w[public pg_catalog],
      sql: "SELECT current_schema() FROM pg_sleep(0.05) /* dashboard_cache_probe */")

    expect([@fills.size, values]).to eq([2, %w[public pg_catalog]])
  end

  it "releases the fill lock after PostgreSQL rejects a query" do
    connection = ActiveRecord::Base.connection
    begin
      AhoyDashboard::AnalyticsCache.fetch(key: key, connection: connection) { connection.select_value("SELECT 1 / 0") }
    rescue ActiveRecord::StatementInvalid
      # A failed fill must leave the entry available for the next request.
    end

    expect(concurrently).to eq([3, 3, 3, 3])
  end

  it "caches a nil aggregate without repeatedly querying PostgreSQL" do
    values = concurrently(sql: "SELECT NULL FROM pg_sleep(0.05) /* dashboard_cache_probe */")

    expect([@fills.size, values]).to eq([1, [nil, nil, nil, nil]])
  end
end
