module AhoyDashboard
  # One report card, or the same card blown up into the details modal. Wraps a
  # BreakdownQuery::Result so the view only ever asks for a label, a bar width
  # and a column of numbers.
  class ReportPresenter
    PATH_DIMENSIONS = %w[page entry_page exit_page].freeze
    DEVICE_DIMENSIONS = %w[device].freeze
    COUNTRY_DIMENSIONS = %w[country].freeze
    DETAILS_VIEW = "details".freeze
    RATE_SUFFIX = "_rate".freeze
    PROPERTY_PREFIX = AhoyDashboard::Dimension::PROPERTY_PREFIX

    DEVICE_LABELS = {
      "desktop" => "Desktop",
      "mobile" => "Mobile",
      "tablet" => "Tablet"
    }.freeze

    HEADINGS = {
      "channel" => "Channel", "source" => "Source", "referrer" => "Referrer",
      "page" => "Page", "entry_page" => "Entry page", "exit_page" => "Exit page",
      "entry_url" => "Entry URL", "entry_host" => "Hostname", "page_group" => "Page group",
      "controller" => "Controller", "country" => "Country", "region" => "Region", "city" => "City",
      "browser" => "Browser", "os" => "OS", "device" => "Screen size", "goal" => "Goal"
    }.freeze

    SMALLEST_PERCENT = 0.1

    Option = Data.define(:label, :value, :params, :path, :active) do
      def active?
        active
      end
      def to_ary
        [ label, value ]
      end

      delegate :first, :last, :[], :each, :size, to: :to_ary
    end

    # A metric the query returned. Most of them are registry metrics; the goals
    # card answers in keys the registry does not carry (events, conversion
    # rate), so those format themselves.
    Column = Data.define(:key, :label, :short, :metric) do
      # nil is not zero. A goal that carries no money has no revenue, and
      # printing $0.00 there would claim the conversion earned nothing rather
      # than that the question does not apply.
      def format(value)
        return "" if value.nil?
        return metric.format(value) if metric

        rate? ? "#{value.to_f.round}%" : ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
      end

      def compact(value)
        return "" if value.nil?
        return metric.compact(value) if metric

        rate? ? "#{value.to_f.round}%" : AhoyDashboard::CompactNumber.call(value)
      end

      def rate?
        key.to_s.end_with?(RATE_SUFFIX)
      end
    end

    class Row
      attr_reader :row

      def initialize(row:, presenter:)
        @row = row
        @presenter = presenter
      end

      def label
        row.label
      end

      def value
        row.value
      end

      def metrics
        row.metrics || {}
      end

      def unknown?
        row.value.blank?
      end

      def display_label
        presenter.display_label(row)
      end

      def share
        presenter.share(row)
      end

      # A different question from #share, and both are on screen at once. The bar
      # is drawn against the biggest row in the card; this is the row's cut of
      # everybody, which is the number somebody reads when they hover it.
      def percent
        presenter.percent_of_total(row)
      end

      def metric_values
        presenter.columns.each_with_object({}) { |column, values| values[column.key] = metric_value(column) }
      end

      def metric_value(column)
        presenter.details? ? column.format(metrics[column.key]) : column.compact(metrics[column.key])
      end

      def raw_values
        presenter.columns.map { |column| metrics[column.key] }
      end

      def filter_params
        presenter.filter_params(row)
      end

      def filter_path
        presenter.filter_path(row)
      end

      def filtered?
        !presenter.applied_filter_index(row).nil?
      end

      def toggle_params
        presenter.toggle_params(row)
      end

      private

      attr_reader :presenter
    end

    attr_reader :query, :report, :tab, :result, :page, :per_page

    def initialize(query:, result:, report: nil, tab: nil, page: 1, details: false, dimension: nil,
                   property_keys: nil, per_page: nil)
      @query = query
      @report = report
      @tab = tab
      @result = result
      @page = [ page.to_i, 1 ].max
      @details = details
      @dimension = dimension
      @property_keys = property_keys && Array(property_keys)
      @per_page = per_page
    end

    def property_keys
      Array(@property_keys)
    end

    def title
      report&.title
    end

    def details?
      @details
    end

    def frame_id
      "report_#{report&.key}"
    end

    def details_frame_id
      "report_details_#{report&.key}"
    end

    def dimension
      @dimension ||= tab&.dimension
    end

    def rows
      @rows ||= Array(result&.rows).map { |row| Row.new(row: row, presenter: self) }
    end

    def empty?
      rows.empty?
    end

    def total
      result.respond_to?(:total) ? result.total.to_i : 0
    end

    def more?
      result.respond_to?(:more?) && result.more?
    end

    def label_column
      tab&.label_column
    end

    def label_heading
      HEADINGS.fetch(dimension.key) { label_column.presence || dimension.label }
    end

    def percent_title
      column = columns.first
      return "Share of the total" if column.nil?

      "Share of all #{column.label.downcase}"
    end

    def count_label
      shown = rows.size
      first = offset + 1
      last = offset + shown

      if more?
        page > 1 ? "Rows #{first} to #{last}" : "Top #{shown}"
      elsif page > 1
        "Rows #{first} to #{last} of #{last}"
      else
        "#{shown} #{"value".pluralize(shown)}"
      end
    end

    def columns
      @columns ||= metric_keys.map { |key| column_for(key) }
    end
    alias_method :metric_columns, :columns

    def header_row
      [ label_column, *columns.map(&:label) ]
    end

    def tabs
      Array(report&.tabs).map do |candidate|
        params = tab_params(candidate)

        Option.new(
          label: candidate.label,
          value: candidate.key,
          params: params,
          path: routes.report_path(report.key, params),
          active: candidate.key == tab.key
        )
      end
    end

    def property?
      tab&.property_tab? && dimension.property? && !no_properties?
    end

    def no_properties?
      tab&.property_tab? && !@property_keys.nil? && @property_keys.empty?
    end

    def property_name
      dimension.key.delete_prefix(PROPERTY_PREFIX)
    end

    def property_options
      return [] unless property?

      @property_options ||= property_keys.map do |name|
        params = card_params.merge(property: name)

        Option.new(
          label: name,
          value: name,
          params: params,
          path: routes.report_path(report.key, params),
          active: name == property_name
        )
      end
    end

    # Which property is showing is part of the card's state, not the tab's, so it
    # rides along on every link the card builds. The details modal and the CSV
    # both have to group by whichever key the card in front of somebody is
    # grouping by, and the tab key alone does not say which that is.
    # Both per-card overrides ride along, because everything built off this is a
    # link back to the same card: the Details modal, the pager inside it, and the
    # CSV. Leave either one out and the download reports a different grouping than
    # the card it came from.
    def card_params
      params = query.to_query.merge(tab: tab.key)
      params = params.merge(property: property_name) if property?
      params = params.merge(breakdown: tab.active_breakdown.key) if tab.active_breakdown

      params
    end

    def card_path
      routes.report_path(report.key, card_params)
    end

    def details_params(page_number = 1)
      params = card_params.merge(view: DETAILS_VIEW)
      page_number > 1 ? params.merge(page: page_number) : params
    end

    def details_path(page_number = 1)
      routes.report_path(report.key, details_params(page_number))
    end

    def next_path
      details_path(page + 1) if more?
    end

    def previous_path
      details_path(page - 1) if page > 1
    end

    def export_path
      routes.export_path(report.key, card_params)
    end

    # The same grouping this card is showing, handed to the surface that can
    # change it. The dimension and the columns go over explicitly because explore
    # holds them and QueryForm does not; anything the dimension cannot answer is
    # dropped there rather than printed as zero.
    def explore_path
      params = query.to_query.merge(
        dimension: dimension.key,
        columns: Array(tab&.detail_metrics).join(",").presence
      )

      routes.explore_path(params.compact)
    end

    def display_label(row)
      return row.label.to_s if row.value.blank?

      # A goal label is not humanized. It is either a name somebody typed or the
      # event name itself, and rewriting either one makes the row stop matching
      # the definition on the settings screen.
      case dimension.key
      when *COUNTRY_DIMENSIONS then Countries.name(row.label)
      when *DEVICE_DIMENSIONS then DEVICE_LABELS.fetch(row.label.to_s.downcase, row.label.to_s.humanize)
      when *PATH_DIMENSIONS then row.label.to_s
      else row.label.to_s
      end
    end

    # Scaled against the biggest row in this card rather than the range total,
    # which is what Plausible does: the top row always fills the card and every
    # other row is read against it. Dividing by the total instead left a card
    # whose winner held a third of the traffic looking like a broken stub.
    def share(row)
      denominator = largest_value

      return 0.0 unless denominator.positive?

      (row.metrics&.values&.first.to_f / denominator).clamp(0.0, 1.0)
    end

    # Rounds to a whole percent above ten and one decimal below it, so a row
    # holding half a percent does not print as zero. Anything at or above 99.5
    # says 100 rather than rounding to it and looking like a bug beside a row
    # that is genuinely everything.
    def percent_of_total(row)
      return nil unless total.positive?

      value = row.metrics&.values&.first.to_f / total * 100

      return "100%" if value >= 99.5
      return "0%" if value.zero?
      return "<#{SMALLEST_PERCENT}%" if value.round(1) < SMALLEST_PERCENT

      value >= 10 ? "#{value.round}%" : "#{value.round(1)}%"
    end

    def filter_params(row)
      query.filter_link_params(dimension.key, row.value)
    end

    def filter_path(row)
      routes.dashboard_path(filter_params(row))
    end

    def applied_filter_index(row)
      query.filters.pinned_index(dimension.key, row.value.presence || dimension.unknown_label)
    end

    def toggle_params(row)
      index = applied_filter_index(row)
      index.nil? ? filter_params(row) : query.without_filter_params(index)
    end

    def as_json(*)
      {
        key: report.key,
        title: title,
        tab: tab.key,
        details: details?,
        page: page,
        more: more?,
        total: total,
        columns: columns.map { |column| { key: column.key, label: column.label, short: column.short } },
        rows: rows.map do |row|
          {
            label: row.display_label,
            value: row.value,
            share: row.share,
            metrics: row.metrics,
            path: row.filter_path
          }
        end
      }
    end

    private

    def metric_keys
      keys = details? ? tab.detail_metrics : tab.metrics

      Array(keys).map(&:to_s)
    end

    def column_for(key)
      metric = lookup_metric(key)

      Column.new(
        key: key,
        label: metric&.label || key.humanize,
        short: metric&.short || key.humanize,
        metric: metric
      )
    end

    def offset
      return 0 unless per_page.to_i.positive?

      (page - 1) * per_page.to_i
    end

    def lookup_metric(key)
      AhoyDashboard::Metric.find_by_key(key)
    end

    # Memoized because #share asks for it once per row, so without this the bar
    # widths are quadratic in the row count. The details modal renders a hundred.
    def largest_value
      @largest_value ||= rows.map { |row| row.metrics.values.first.to_f }.max.to_f
    end

    def tab_params(candidate)
      params = query.to_query.merge(tab: candidate.key)
      params = params.merge(view: DETAILS_VIEW) if details?
      params
    end

    def routes
      AhoyDashboard::Engine.routes.url_helpers
    end
  end
end
