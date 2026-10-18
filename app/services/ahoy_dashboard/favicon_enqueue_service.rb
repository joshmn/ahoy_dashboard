# frozen_string_literal: true

module AhoyDashboard
  class FaviconEnqueueService
    PENDING_TTL = 10.minutes

    class << self
      def call(domain:)
        new(domain: domain).call
      end
    end

    def initialize(domain:)
      @domain = domain
    end

    def call
      return if AhoyDashboard.cache.is_a?(ActiveSupport::Cache::NullStore)
      return if FaviconFetchJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)
      return if AhoyDashboard.cache.exist?(FaviconService.cache_key(domain))
      return unless AhoyDashboard.cache.write(pending_key, true, expires_in: PENDING_TTL, unless_exist: true)

      FaviconFetchJob.perform_later(domain)
    rescue StandardError => error
      AhoyDashboard.cache.delete(pending_key)
      Rails.logger.warn("favicon enqueue failed: #{error.class}: #{error.message}")
      nil
    end

    private

    attr_reader :domain

    def pending_key
      "ahoy_dashboard/favicons/pending/#{domain}"
    end
  end
end
