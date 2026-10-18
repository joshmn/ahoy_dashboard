module AhoyDashboard
  module Reports
    class DigestQuery
      METRICS = %w[visitors visits pageviews bounce_rate].freeze

      LISTS = [
        { key: :pages, title: "Top pages", dimension: "page" },
        { key: :sources, title: "Top sources", dimension: "source" },
        { key: :countries, title: "Top countries", dimension: "country" }
      ].freeze

      Row = Data.define(:label, :value, :visitors, :share)
      List = Data.define(:key, :title, :dimension, :rows) do
        def any?
          rows.any?
        end
      end

      Result = Data.define(:window, :stats, :lists) do
        def stat(key)
          stats.find { |candidate| candidate.metric.key == key.to_s }
        end

        def visitors
          stat("visitors")&.value.to_i
        end

        def empty?
          visitors.zero?
        end

        def list(key)
          lists.find { |candidate| candidate.key == key }
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(window:, limit: Digests::ROW_LIMIT)
        @window = window
        @limit = limit
      end

      def call
        current = scope_for(window)
        previous = scope_for(window.previous)

        Result.new(
          window: window,
          stats: AhoyDashboard::TopStatsQuery.call(scope: current, comparison_scope: previous, metrics: METRICS),
          lists: LISTS.map { |list| build(list, current) }
        )
      end

      private

      attr_reader :window, :limit

      def scope_for(window)
        AhoyDashboard::ScopeQuery.call(range: window.range, filters: AhoyDashboard::Filters.new([]))
      end

      def build(list, scope)
        dimension = AhoyDashboard::Dimension.find(list[:dimension])
        result = AhoyDashboard::BreakdownQuery.call(scope: scope, dimension: dimension,
                                                    metrics: %w[visitors], limit: limit)

        List.new(key: list[:key], title: list[:title], dimension: dimension,
                 rows: result.rows.map { |row| row_for(row, result.total) })
      end

      def row_for(row, total)
        visitors = row.metrics["visitors"].to_i

        Row.new(label: row.label, value: row.value, visitors: visitors,
                share: total.to_i.zero? ? 0.0 : (visitors * 100.0 / total))
      end
    end
  end
end
