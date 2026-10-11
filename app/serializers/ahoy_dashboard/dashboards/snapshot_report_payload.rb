# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotReportPayload
      class << self
        def dump(reading:)
          tab = reading.fetch(:tab)
          breakdown = tab.active_breakdown
          {
            "report" => reading.fetch(:report).key, "tab" => tab.key,
            "dimension" => reading.fetch(:dimension).key, "breakdown" => breakdown && breakdown.key,
            "details" => reading.fetch(:details), "page" => reading.fetch(:page),
            "property_keys" => reading.fetch(:property_keys), "per_page" => reading.fetch(:per_page),
            "result" => dump_result(result: reading.fetch(:result))
          }
        end

        def load(payload:)
          report = Report.find_by_key(payload.fetch("report"))
          raise SnapshotPayload::MissingDefinition, "Missing report" unless report

          tab = report.tabs.find { |candidate| candidate.key == payload.fetch("tab") }
          dimension = Dimension.find_by_key(payload.fetch("dimension"))
          raise SnapshotPayload::MissingDefinition, "Missing report tab or dimension" unless tab && dimension

          tab = tab.for_breakdown(payload.fetch("breakdown")).with(dimension_key: dimension.key)
          { report: report, tab: tab, dimension: dimension, result: load_result(payload: payload.fetch("result")),
            details: payload.fetch("details"), page: payload.fetch("page"),
            property_keys: payload.fetch("property_keys"), per_page: payload.fetch("per_page") }
        end

        def dump_result(result:)
          return unless result

          { "rows" => result.rows.map { |row| [row.label, row.value, row.metrics] },
            "total" => result.total, "more" => result.more }
        end

        def load_result(payload:)
          return unless payload

          rows = payload.fetch("rows").map do |label, value, metrics|
            BreakdownQuery::Row.new(label: label, value: value, metrics: metrics)
          end
          BreakdownQuery::Result.new(rows: rows, total: payload.fetch("total"), more: payload.fetch("more"))
        end
      end
    end
  end
end
