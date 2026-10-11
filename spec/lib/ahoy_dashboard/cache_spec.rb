# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard cache selection" do
  around do |example|
    previous_store = AhoyDashboard.config.cache_store
    previous_cache = Rails.cache
    AhoyDashboard.config.cache_store = nil
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    AhoyDashboard.config.cache_store = previous_store
    Rails.cache = previous_cache
  end

  it "follows the current Rails cache when no store is configured" do
    AhoyDashboard.cache
    Rails.cache = ActiveSupport::Cache::NullStore.new

    expect(AhoyDashboard.cache).to be(Rails.cache)
  end

  it "uses the initializer's store without replacing the host cache" do
    host_cache = Rails.cache
    AhoyDashboard.configure { |config| config.cache_store = :memory_store }

    expect(Rails.cache).to be(host_cache)
  end

  it "reads analytical results from the selected store" do
    AhoyDashboard.config.cache_store = :memory_store
    connection = AhoyDashboard.visit.connection
    key = AhoyDashboard::AnalyticsCache.key(key: "selected", connection: connection)
    Rails.cache.write(key, "host")
    AhoyDashboard.cache.write(key, "dashboard")

    expect(AhoyDashboard::AnalyticsCache.fetch(key: "selected", connection: connection) { "uncached" }).to eq("dashboard")
  end

  it "publishes analytical results to the selected store" do
    AhoyDashboard.config.cache_store = :memory_store
    connection = AhoyDashboard.visit.connection
    AhoyDashboard::AnalyticsCache.write(key: "selected", value: 42, connection: connection)
    key = AhoyDashboard::AnalyticsCache.key(key: "selected", connection: connection)

    expect([AhoyDashboard.cache.read(key), Rails.cache.read(key)]).to eq([42, nil])
  end

  it "returns to the current host cache when the override is removed" do
    AhoyDashboard.config.cache_store = :memory_store
    AhoyDashboard.config.cache_store = nil

    expect(AhoyDashboard.cache).to be(Rails.cache)
  end
end
