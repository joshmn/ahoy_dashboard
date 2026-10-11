# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::FaviconEnqueueService do
  around do |example|
    previous_store = AhoyDashboard.config.cache_store
    previous_cache = Rails.cache
    previous_adapter = AhoyDashboard::FaviconFetchJob.queue_adapter
    AhoyDashboard.config.cache_store = :memory_store
    Rails.cache = ActiveSupport::Cache::NullStore.new
    AhoyDashboard::FaviconFetchJob.queue_adapter = :test
    example.run
  ensure
    AhoyDashboard.config.cache_store = previous_store
    Rails.cache = previous_cache
    AhoyDashboard::FaviconFetchJob.queue_adapter = previous_adapter
  end

  it "deduplicates fetches in the selected store when the host has no cache" do
    2.times { described_class.call(domain: "example.com") }

    expect(AhoyDashboard::FaviconFetchJob.queue_adapter.enqueued_jobs.length).to eq(1)
  end

  it "uses an icon already in the selected store" do
    AhoyDashboard.cache.write("#{AhoyDashboard::FaviconService::ICON_KEY}/example.com", "cached")
    described_class.call(domain: "example.com")

    expect(AhoyDashboard::FaviconFetchJob.queue_adapter.enqueued_jobs).to be_empty
  end

  it "skips fetches when the selected store cannot retain icons" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    AhoyDashboard.config.cache_store = :null_store
    described_class.call(domain: "example.com")

    expect(AhoyDashboard::FaviconFetchJob.queue_adapter.enqueued_jobs).to be_empty
  end
end
