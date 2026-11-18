module AhoyDashboard
  module Assistant
    class View
      SERIES = "series".freeze
      TABLE = "table".freeze
      FIGURES = "figures".freeze
      PROMPTS = "prompts".freeze
      KINDS = [ SERIES, TABLE, FIGURES, PROMPTS ].freeze

      MAX_ROWS = 25
      MAX_POINTS = 400

      attr_reader :kind, :title, :subtitle, :path, :path_label, :metric_key, :interval,
                  :columns, :rows, :figures, :points

      def self.series(title:, points:, metric_key: nil, interval: "day", **rest)
        new(kind: SERIES, title: title, points: points, metric_key: metric_key,
            interval: interval, **rest)
      end

      def self.table(title:, columns:, rows:, **rest)
        new(kind: TABLE, title: title, columns: columns, rows: rows, **rest)
      end

      def self.figures(title:, figures:, **rest)
        new(kind: FIGURES, title: title, figures: figures, **rest)
      end

      def self.prompts(title:, rows:, **rest)
        new(kind: PROMPTS, title: title, rows: rows, **rest)
      end

      def self.from(stored)
        hash = stored.to_h.symbolize_keys
        return nil unless KINDS.include?(hash[:kind].to_s)

        new(**hash.slice(:kind, :title, :subtitle, :path, :path_label, :metric_key, :interval,
                         :columns, :rows, :figures, :points))
      rescue StandardError
        nil
      end

      def initialize(kind:, title:, subtitle: nil, path: nil, path_label: nil, metric_key: nil,
                     interval: nil, columns: nil, rows: nil, figures: nil, points: nil)
        @kind = kind.to_s
        @title = title.to_s
        @subtitle = subtitle.presence
        @path = path.presence
        @path_label = path_label.presence
        @metric_key = metric_key.presence
        @interval = interval.presence
        @columns = Array(columns).map { |column| column.to_h.symbolize_keys }
        @rows = Array(rows).first(MAX_ROWS).map { |row| row.to_h.symbolize_keys }
        @figures = Array(figures).map { |figure| figure.to_h.symbolize_keys }
        @points = Array(points).last(MAX_POINTS).map { |at, value| [ stamp(at), value ] }
        @rows_cut = [ Array(rows).size - MAX_ROWS, 0 ].max
        @points_cut = [ Array(points).size - MAX_POINTS, 0 ].max
      end

      attr_reader :rows_cut, :points_cut

      def series?
        kind == SERIES
      end

      def table?
        kind == TABLE
      end

      def figures?
        kind == FIGURES
      end

      def prompts?
        kind == PROMPTS
      end

      def drawable?
        return points.size >= 2 if series?
        return rows.any? if table? || prompts?

        figures.any?
      end

      def metric
        @metric ||= AhoyDashboard::Metric.find_by_key(metric_key.to_s) || AhoyDashboard::Metric.default
      end

      def stamp(at)
        at.respond_to?(:iso8601) ? at.iso8601 : at.to_s
      end
      private :stamp

      def to_h
        {
          kind: kind, title: title, subtitle: subtitle, path: path, path_label: path_label,
          metric_key: metric_key, interval: interval, columns: columns, rows: rows,
          figures: figures, points: points
        }.reject { |_key, value| value.blank? }
      end
    end
  end
end
