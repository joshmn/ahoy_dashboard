# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotSearchConsolePayload
      class << self
        def dump(reading:)
          return unless reading

          { "range" => SnapshotPayload.dump_range(range: reading.range),
            "queries" => reading.queries.map { |row| row.to_h.stringify_keys },
            "pages" => reading.pages.map { |row| row.to_h.stringify_keys },
            "totals" => reading.totals.to_h.stringify_keys, "coverage" => reading.coverage.to_h.stringify_keys,
            "live_dates" => reading.live_dates.map(&:iso8601), "connected" => reading.connected,
            "problem" => reading.problem, "through" => reading.through && reading.through.iso8601 }
        end

        def load(payload:)
          return unless payload

          SearchConsoleQuery::Result.new(range: SnapshotPayload.load_range(payload: payload.fetch("range")),
            queries: payload.fetch("queries").map { |row| load_row(row) },
            pages: payload.fetch("pages").map { |row| load_row(row) },
            totals: SearchConsoleQuery::Totals.new(**payload.fetch("totals").symbolize_keys),
            coverage: SearchConsoleQuery::Coverage.new(**payload.fetch("coverage").symbolize_keys),
            live_dates: payload.fetch("live_dates").map { |date| Date.iso8601(date) },
            connected: payload.fetch("connected"), problem: payload.fetch("problem"),
            through: (Date.iso8601(payload.fetch("through")) if payload.fetch("through")))
        end

        private

        def load_row(row)
          SearchConsoleQuery::Row.new(label: row.fetch("label"), clicks: row.fetch("clicks"),
            impressions: row.fetch("impressions"), ctr: row.fetch("ctr"), position: row.fetch("position"))
        end
      end
    end
  end
end
