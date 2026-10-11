# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotJourneyPayload
      class << self
        def dump(reading:)
          return unless reading

          columns = reading.columns.map do |column|
            rows = column.rows.map { |row| [row.step.value, row.visitors, row.share, row.chosen] }
            { "index" => column.index, "chain" => column.chain.map(&:value), "search" => column.search,
              "rows" => rows, "reached" => column.reached, "more" => column.more }
          end
          { "chain" => reading.chain.map(&:value), "limit" => reading.limit,
            "columns" => columns, "entered" => reading.entered }
        end

        def load(payload:)
          return unless payload

          columns = payload.fetch("columns").map do |column|
            rows = column.fetch("rows").map do |value, visitors, share, chosen|
              JourneyQuery::Row.new(step: JourneyQuery::Step.new(value: value), visitors: visitors,
                share: share, chosen: chosen)
            end
            JourneyQuery::Column.new(index: column.fetch("index"), chain: load_chain(column.fetch("chain")),
              search: column.fetch("search"), rows: rows, reached: column.fetch("reached"), more: column.fetch("more"))
          end
          JourneyQuery::Result.new(chain: load_chain(payload.fetch("chain")), limit: payload.fetch("limit"),
            columns: columns, entered: payload.fetch("entered"))
        end

        private

        def load_chain(values)
          values.map { |value| JourneyQuery::Step.new(value: value) }
        end
      end
    end
  end
end
