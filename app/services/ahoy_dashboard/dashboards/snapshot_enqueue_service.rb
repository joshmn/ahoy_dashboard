# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotEnqueueService
      LEASE = 1.minute

      class << self
        def call(expected_key: nil)
          return unless Preferences.read(:site, :precomputed_dashboard)
          return if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
          return if SnapshotRefreshJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)

          expected_key ||= default_key
          return unless expected_key

          SnapshotLockService.call(key: "#{expected_key}/queue", wait: false) do
            next if SnapshotStore.read_value(key: lease_key(expected_key))

            token = SecureRandom.uuid
            SnapshotStore.write_value(key: lease_key(expected_key), value: token, expires_in: LEASE)
            begin
              job = SnapshotRefreshJob.perform_later(expected_key, token)
              raise job.enqueue_error if job && job.respond_to?(:enqueue_error) && job.enqueue_error
              SnapshotStore.delete(key: lease_key(expected_key)) unless job
              job
            rescue StandardError => error
              SnapshotStore.delete(key: lease_key(expected_key))
              Rails.logger.warn("Dashboard snapshot refresh enqueue failed: #{error.class}: #{error.message}")
              nil
            end
          end
        end

        def release(expected_key:, token:)
          SnapshotLockService.call(key: "#{expected_key}/queue") do
            if SnapshotStore.read_value(key: lease_key(expected_key)) == token
              SnapshotStore.delete(key: lease_key(expected_key))
            end
          end
        end

        private

        def default_key
          query = QueryForm.from_params({period: "30d", filters: "none"})
          return unless SnapshotQuery.eligible?(query: query, cards: true)

          SnapshotKeyQuery.call(query: query)
        end

        def lease_key(key)
          "#{key}/refresh"
        end
      end
    end
  end
end
