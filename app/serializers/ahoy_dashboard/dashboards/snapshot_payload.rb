# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotPayload
      class MissingDefinition < StandardError; end

      class << self
        def dump(reading:)
          {
            "stats" => reading.readings.stats.map { |stat| [stat.metric.key, stat.value, stat.comparison_value, stat.change] },
            "series" => dump_series(reading.readings.series),
            "comparison_series" => dump_series(reading.readings.comparison_series),
            "annotation_ids" => reading.annotations.map(&:id),
            "reports" => reading.reports.map { |report| SnapshotReportPayload.dump(reading: report) },
            "pinned_cards" => SnapshotFeaturePayload.dump_pinned(readings: reading.pinned_cards),
            "funnels" => SnapshotFeaturePayload.dump_funnels(readings: reading.funnels),
            "funnel_count" => reading.funnel_count,
            "search_console" => SnapshotSearchConsolePayload.dump(reading: reading.search_console),
            "journey" => SnapshotJourneyPayload.dump(reading: reading.journey),
            "goal_conversions" => SnapshotReportPayload.dump_result(result: reading.goal_conversions)
          }
        end

        def load(payload:, computed_at:, realtime:, snapshot_key: nil)
          Reading.new(**summary(payload: payload, realtime: realtime), computed_at: computed_at, snapshot_key: snapshot_key,
            reports: payload.fetch("reports").map { |report| SnapshotReportPayload.load(payload: report) },
            pinned_cards: SnapshotFeaturePayload.load_pinned(payload: payload.fetch("pinned_cards")),
            funnels: SnapshotFeaturePayload.load_funnels(payload: payload.fetch("funnels")),
            funnel_count: payload.fetch("funnel_count"), search_console_state: FeatureState.for(:search_console),
            search_console: SnapshotSearchConsolePayload.load(payload: payload.fetch("search_console")),
            journey: SnapshotJourneyPayload.load(payload: payload.fetch("journey")),
            goal_conversions: SnapshotReportPayload.load_result(payload: payload.fetch("goal_conversions")),
            goals: payload.fetch("goal_conversions") ? Goal.ordered.to_a : [])
        end

        def summary(payload:, realtime:)
          stats = payload.fetch("stats").map do |key, value, previous, change|
            metric = Metric.find_by_key(key) || raise(MissingDefinition, "Missing metric #{key}")
            TopStatsQuery::Stat.new(metric: metric, value: value, comparison_value: previous, change: change)
          end
          readings = TopStatsQuery::WithSeries.new(stats: stats, series: load_series(payload.fetch("series")),
            comparison_series: load_series(payload.fetch("comparison_series")))
          { readings: readings, realtime: realtime,
            annotations: records(model: Annotation, ids: payload.fetch("annotation_ids")) }
        end

        def records(model:, ids:)
          return [] if ids.empty?

          found = model.where(id: ids).index_by(&:id)
          ids.map { |id| found.fetch(id) { raise MissingDefinition, "Missing #{model.name} #{id}" } }
        end

        def dump_range(range:)
          [range.begin.iso8601(9), range.end.iso8601(9), range.exclude_end?]
        end

        def load_range(payload:)
          Range.new(load_time(payload.fetch(0)), load_time(payload.fetch(1)), payload.fetch(2))
        end

        private

        def dump_series(series)
          series.map { |time, value| [time.iso8601(9), value] } if series
        end

        def load_series(payload)
          payload.map { |time, value| [load_time(time), value] } if payload
        end

        def load_time(value)
          Time.iso8601(value).in_time_zone(AhoyDashboard.time_zone)
        end
      end
    end
  end
end
