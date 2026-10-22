module AhoyDashboard
  class ReportPresenter
    DETAILS_VIEW = "details".freeze
    FRAME_PREFIX = "report_".freeze
    DETAILS_FRAME_PREFIX = "report_details_".freeze
    PROPERTY_PREFIX = AhoyDashboard::Dimension::PROPERTY_PREFIX

    HEADINGS = {
      "channel" => "Channel", "source" => "Source", "referrer" => "Referrer",
      "page" => "Page", "entry_page" => "Entry page", "exit_page" => "Exit page",
      "entry_url" => "Entry URL", "entry_host" => "Hostname", "page_group" => "Page group",
      "controller" => "Controller", "country" => "Country", "region" => "Region", "city" => "City",
      "browser" => "Browser", "os" => "OS", "device" => "Screen size", "goal" => "Goal"
    }.freeze

    class << self
      def frame_id(report)
        "#{FRAME_PREFIX}#{report.key}"
      end

      def details_frame_id(report)
        "#{DETAILS_FRAME_PREFIX}#{report.key}"
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

      def display_label
        presenter.display_label(row)
      end

      def share
        presenter.share(row)
      end

      def percent
        presenter.percent_of_total(row)
      end

      def metric_value(metric)
        value = metrics[metric.key]
        return "" if value.nil?

        presenter.details? ? metric.format(value) : metric.compact(value)
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

    attr_reader :query, :report, :tab, :result, :page, :per_page, :term

    def initialize(query:, result:, report: nil, tab: nil, page: 1, details: false, dimension: nil,
                   property_keys: nil, per_page: nil, term: nil)
      @query = query
      @report = report
      @tab = tab
      @result = result
      @page = [ page.to_i, 1 ].max
      @details = details
      @dimension = dimension
      @property_keys = property_keys && Array(property_keys)
      @per_page = per_page
      @term = term
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
      self.class.frame_id(report)
    end

    def details_frame_id
      self.class.details_frame_id(report)
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
      @columns ||= metric_keys.map { |key| AhoyDashboard::Metric.find(key) }
    end

    def header_row
      [ label_column, *columns.map(&:label) ]
    end

    def csv_rows
      Enumerator.new do |out|
        out << header_row
        rows.each { |row| out << [ row.display_label, *row.raw_values ] }
      end
    end

    def csv_filename
      "ahoy-dashboard-#{report.key}-#{today}.csv"
    end

    def tabs
      @tabs ||= Array(report&.tabs).map do |candidate|
        AhoyDashboard::MenuOption.new(
          label: candidate.label,
          value: candidate.key,
          path: routes.report_path(report.key, link_params(tab: candidate.key)),
          active: candidate.key == tab.key
        )
      end
    end

    def breakdown_options
      @breakdown_options ||= Array(tab&.breakdown_options).map do |option|
        AhoyDashboard::MenuOption.new(
          label: option.label,
          value: option.key,
          path: routes.report_path(report.key, link_params(tab: tab.key, breakdown: option.key)),
          active: option == tab.active_breakdown
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
        AhoyDashboard::MenuOption.new(
          label: name,
          value: name,
          path: routes.report_path(report.key, card_params.merge(property: name).merge(view_params)),
          active: name == property_name
        )
      end
    end

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
      params = params.merge(page: page_number) if page_number > 1
      term.present? ? params.merge(q: term) : params
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

    def clear_search_path
      routes.report_path(report.key, details_params.except(:q))
    end

    def export_path
      routes.export_path(report.key, card_params)
    end

    def explore_path
      params = query.to_query.merge(
        dimension: dimension.key,
        columns: Array(tab&.detail_metrics).join(",").presence
      )

      routes.explore_path(params.compact)
    end

    def display_label(row)
      label = row.label.to_s
      return label if row.value.blank?

      case dimension.key
      when "country" then Countries.name(row.label)
      when "device" then label.humanize
      else label
      end
    end

    def share(row)
      AhoyDashboard::Share.fraction(row.metrics&.values&.first, of: largest_value)
    end

    def percent_of_total(row)
      AhoyDashboard::Share.label(row.metrics&.values&.first, of: total)
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

    def offset
      return 0 unless per_page.to_i.positive?

      (page - 1) * per_page.to_i
    end

    def today
      Time.current.in_time_zone(AhoyDashboard.time_zone).to_date.iso8601
    end

    def largest_value
      @largest_value ||= rows.map { |row| row.metrics.values.first.to_f }.max.to_f
    end

    def link_params(overrides)
      query.to_query.merge(overrides).merge(view_params)
    end

    def view_params
      details? ? { view: DETAILS_VIEW } : {}
    end

    def routes
      AhoyDashboard.routes
    end
  end
end
