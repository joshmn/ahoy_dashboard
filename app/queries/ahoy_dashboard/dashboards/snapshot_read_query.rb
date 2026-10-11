# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotReadQuery
      class << self
        def call(query:, section:, id: nil)
          return unless SnapshotQuery.eligible?(query: query, cards: true)

          key = SnapshotKeyQuery.call(query: query)
          snapshot = SnapshotStore.read(key: key)
          SnapshotEnqueueService.call(expected_key: key) unless snapshot && snapshot.fresh?
          return unless snapshot && snapshot.usable?

          SnapshotPanelPayload.load(snapshot: snapshot, snapshot_key: key, section: section, id: id)
        rescue SnapshotPayload::MissingDefinition
          nil
        end
      end
    end
  end
end
