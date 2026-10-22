module AhoyDashboard
  class DashboardPresenter
    PERCENT_METRICS = %w[bounce_rate scroll_depth].freeze
    PREVIOUS_PERIOD = "previous_period".freeze

    INTERVAL_LABELS = {
      minute: "Minute",
      five_minutes: "5 minutes",
      fifteen_minutes: "15 minutes",
      hour: "Hour",
      day: "Day",
      week: "Week",
      month: "Month"
    }.freeze

    COMPARISON_LABELS = {
      nil => "No comparison",
      PREVIOUS_PERIOD => "Previous period",
      "year_over_year" => "Year over year"
    }.freeze

    Tile = Data.define(:metric, :value, :display, :full, :comparison_display, :change, :delta, :active, :path) do
      def active?
        active
      end
      def key
        metric.key
      end
      def label
        metric.label
      end
      def short
        metric.short
      end
    end

    attr_reader :query, :stats, :series, :comparison_series, :realtime

    def initialize(query:, stats: [], series: [], comparison_series: nil, realtime: 0, selectable: false, annotations: [])
      @query = query
      @stats = Array(stats)
      @series = AhoyDashboard::Sql::Buckets.elapsed(Array(series))
      @comparison_series = comparison_series
      @realtime = realtime.to_i
      @selectable = selectable
      @annotation_records = annotations
    end

    def tiles
      @tiles ||= stats.map do |stat|
        Tile.new(
          metric: stat.metric,
          value: stat.value,
          display: stat.metric.compact(stat.value),
          full: stat.metric.format(stat.value),
          comparison_display: (stat.metric.compact(stat.comparison_value) if stat.comparison_value),
          change: stat.change,
          delta: delta_for(stat),
          active: stat.metric.key == query.metric.key,
          path: dashboard_path(query.with(metric: stat.metric.key).to_query)
        )
      end
    end

    def chart_data
      return [] if series.blank?

      data = [ { name: query.metric.label, data: points(series) } ]
      data << { name: comparison_name, data: comparison_points } if comparison_points.any?
      data
    end

    def chart_options
      {
        library: {
          plugins: { tmFormat: chart_format, tmAnnotations: annotations, tmSelect: selection }.compact,
          scales: { y: { max: (100 if PERCENT_METRICS.include?(query.metric.key)) }.compact }
        }
      }
    end

    def annotations
      AhoyDashboard::AnnotationDecorator.wrap(annotation_records).map do |note|
        at = note.local_time

        { at: at.iso8601, label: note.label, kind: note.kind,
          kind_label: note.kind_label, when_label: at.strftime("%b %-d, %-l:%M %P") }
      end
    end

    def selection
      return unless @selectable
      return if query.range.end - query.range.begin <= 1.minute

      params = query.to_query.except(:from, :to, :interval).merge(period: AhoyDashboard::Period::CUSTOM_KEY)

      { url: dashboard_path(params), from: query.range.begin.to_date.iso8601, to: query.range.end.to_date.iso8601 }
    end

    def range_label
      query.range_label
    end

    def comparison_label
      return "vs #{comparison_phrase}" if running? && comparison_phrase.present?

      COMPARISON_LABELS.fetch(query.comparison&.to_s, COMPARISON_LABELS[nil])
    end

    def comparing?
      query.comparison.present?
    end

    def comparison_switch_label
      comparing? ? comparison_label : COMPARISON_LABELS[PREVIOUS_PERIOD]
    end

    def comparison_switch_path
      routes.root_path(query.with(comparison: (PREVIOUS_PERIOD unless comparing?)).to_query)
    end

    def comparison_phrase
      return @comparison_phrase if defined?(@comparison_phrase)

      @comparison_phrase = query.comparison && query.period.comparison_phrase(query.range, query.comparison)
    end

    def running?
      query.period.running?(query.range)
    end

    def interval_options
      query.intervals.map do |interval|
        key = interval.to_sym
        option(
          INTERVAL_LABELS.fetch(key, key.to_s.humanize),
          key.to_s,
          { interval: key.to_s },
          query.interval == key
        )
      end
    end

    def comparison_options
      COMPARISON_LABELS.map do |value, label|
        option(label, value, { comparison: value }, query.comparison&.to_s == value)
      end
    end

    def as_json(*)
      {
        metric: query.metric.key,
        period: query.period.key,
        interval: query.interval.to_s,
        realtime: realtime,
        stats: tiles.map { |tile| tile_json(tile) },
        series: chart_data,
        options: chart_options,
        url: dashboard_path(query.to_query)
      }
    end

    private

    attr_reader :annotation_records

    def delta_for(stat)
      phrase = comparison_phrase.presence || "the previous period"
      return AhoyDashboard::Delta.fresh.merge(title: "None to compare with: #{phrase}") if fresh?(stat)

      delta = AhoyDashboard::Delta.percent(stat.change, inverted: stat.metric&.inverted?)
      return if delta.nil?

      against = stat.metric.compact(stat.comparison_value) unless stat.comparison_value.nil?
      delta.merge(title: against ? "vs #{against}, #{phrase}" : "vs #{phrase}")
    end

    def fresh?(stat)
      !stat.comparison_value.nil? && stat.comparison_value.to_f.zero? && stat.value.to_f.positive?
    end

    def tile_json(tile)
      {
        key: tile.key,
        label: tile.label,
        short: tile.short,
        value: tile.value,
        display: tile.display,
        full: tile.full,
        comparison_display: tile.comparison_display,
        change: tile.change,
        delta: tile.delta,
        active: tile.active?,
        path: tile.path
      }
    end

    def chart_format
      {
        label: query.metric.label,
        value: query.metric.format_type.to_s,
        interval: interval_key,
        partial: query.range.cover?(Time.current)
      }
    end

    def interval_key
      query.interval.to_s
    end

    def points(pairs)
      Array(pairs).map { |time, value| [ time, value ] }
    end

    def comparison_points
      @comparison_points ||= begin
        times = series.map(&:first)
        Array(comparison_series).each_with_index.map do |(_time, value), index|
          [ times[index], value ] if times[index]
        end.select { |value| value }
      end
    end

    def comparison_name
      base = COMPARISON_LABELS.fetch(query.comparison&.to_s, COMPARISON_LABELS[nil])
      base = comparison_phrase.upcase_first if running? && comparison_phrase.present?
      label = comparison_range_label

      label.present? ? "#{base}: #{label}" : base
    end

    def comparison_range_label
      return if query.comparison_range.blank?

      query.period.label_for(query.comparison_range, timed: query.timed?)
    rescue StandardError
      nil
    end

    def option(label, value, overrides, active)
      AhoyDashboard::MenuOption.new(label: label, value: value, path: dashboard_path(query.with(overrides).to_query),
                                    active: active)
    end

    def dashboard_path(params)
      routes.dashboard_path(params)
    end

    def routes
      AhoyDashboard.routes
    end
  end
end
