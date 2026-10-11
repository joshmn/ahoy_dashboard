# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotRefreshService
      class << self
        def call(expected_key: nil, force: false, token: nil)
          new(expected_key: expected_key, force: force, token: token).call
        end
      end

      def initialize(expected_key:, force:, token:)
        @expected_key = expected_key
        @force = force
        @token = token
      end

      def call
        query = default_query
        return unless SnapshotQuery.eligible?(query: query, cards: true)

        key = SnapshotKeyQuery.call(query: query)
        return if expected_key && expected_key != key

        SnapshotLockService.call(key: "#{key}/build") do
          previous = SnapshotStore.read(key: key)
          if !force && previous && previous.fresh?
            previous
          else
            build(query: query, key: key)
          end
        end
      ensure
        SnapshotEnqueueService.release(expected_key: expected_key, token: token) if token && expected_key
      end

      private

      attr_reader :expected_key, :force, :token

      def default_query
        QueryForm.from_params({period: "30d", filters: "none"})
      end

      def build(query:, key:)
        computed_at = Time.current
        reading = ShowQuery.call(query: query, cards: true)
        snapshot = Snapshot.new(payload: SnapshotPayload.dump(reading: reading), computed_at: computed_at)
        return unless SnapshotQuery.eligible?(query: default_query, cards: true)
        return unless SnapshotKeyQuery.call(query: default_query) == key
        return unless snapshot.usable?

        SnapshotStore.write(key: key, snapshot: snapshot)
        snapshot
      end
    end
  end
end
