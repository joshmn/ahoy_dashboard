# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotPanelPayload
      class << self
        def load(snapshot:, snapshot_key:, section:, id: nil)
          payload = snapshot.payload
          attributes = case section
          when :summary then summary(payload)
          when :report then report(payload, id)
          when :pinned then { pinned_cards: SnapshotFeaturePayload.load_pinned(payload: payload.fetch("pinned_cards")) }
          when :funnel then funnel(payload, id)
          when :journey then { journey: SnapshotJourneyPayload.load(payload: payload.fetch("journey")) }
          when :goals then goals(payload)
          when :search_console then { search_console: SnapshotSearchConsolePayload.load(payload: payload.fetch("search_console")) }
          else raise ArgumentError, "Unknown dashboard snapshot section #{section}"
          end
          return unless attributes

          Reading.new(**{ readings: nil, realtime: nil, annotations: [] }.merge(attributes),
            computed_at: snapshot.computed_at, snapshot_key: snapshot_key)
        end

        private

        def summary(payload)
          SnapshotPayload.summary(payload: payload, realtime: RealtimeQuery.call)
        end

        def report(payload, id)
          found = payload.fetch("reports").find { |item| item.fetch("report") == id.to_s }
          { reports: [SnapshotReportPayload.load(payload: found)] } if found
        end

        def funnel(payload, id)
          found = payload.fetch("funnels").find { |item| item.fetch("funnel_id").to_s == id.to_s }
          { funnels: SnapshotFeaturePayload.load_funnels(payload: [found]) } if found
        end

        def goals(payload)
          { goal_conversions: SnapshotReportPayload.load_result(payload: payload.fetch("goal_conversions")),
            goals: Goal.ordered.to_a }
        end
      end
    end
  end
end
