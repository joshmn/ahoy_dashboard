# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotQuery
      class << self
        def call(query:, cards: true)
          new(query: query, cards: cards).call
        end

        def eligible?(query:, cards:)
          Preferences.read(:site, :precomputed_dashboard) && cards &&
            query.period.key == "30d" && query.interval == :day && query.metric.key == "visitors" &&
            query.comparison.nil? && query.filters.empty? && query.default_filters.blank? &&
            !query.include_crawlers? && !query.include_internal?
        end
      end

      def initialize(query:, cards:)
        @query = query
        @cards = cards
      end

      def call
        return live unless self.class.eligible?(query: query, cards: cards)

        key = SnapshotKeyQuery.call(query: query)
        snapshot = SnapshotStore.read(key: key)
        if snapshot && snapshot.usable?
          SnapshotEnqueueService.call(expected_key: key) unless snapshot.fresh?
        else
          snapshot = SnapshotRefreshService.call(expected_key: key)
        end
        return live unless snapshot

        SnapshotPayload.load(payload: snapshot.payload, computed_at: snapshot.computed_at,
          realtime: RealtimeQuery.call, snapshot_key: key)
      rescue SnapshotPayload::MissingDefinition
        live
      end

      private

      attr_reader :query, :cards

      def live
        ShowQuery.call(query: query, cards: cards)
      end
    end
  end
end
