module AhoyDashboard
  class SearchConsolePresenter
    include AhoyDashboard::Seo::Formatting

    FRAME = "report_search_console".freeze
    DETAILS_FRAME = "report_details_search_console".freeze
    DETAILS_VIEW = "details".freeze

    TITLE = "Google search".freeze

    TABS = {
      "queries" => { label: "Queries", column: "Query" },
      "pages" => { label: "Pages", column: "Page" }
    }.freeze

    COLUMNS = [
      { key: "clicks", label: "Clicks", short: "Clicks", heading: "Clicks" },
      { key: "impressions", label: "Impressions", short: "Impr", heading: "Impressions" },
      { key: "ctr", label: "Click through rate", short: "CTR", heading: "CTR" },
      { key: "position", label: "Average position", short: "Pos", heading: "Position" }
    ].freeze

    class Row
      attr_reader :row

      def initialize(row:, presenter:)
        @row = row
        @presenter = presenter
      end

      delegate :label, to: :row

      def display_label
        row.label.presence || AhoyDashboard::SearchConsole::ANONYMIZED_QUERY
      end

      def keyword_path
        presenter.keyword_path(row)
      end

      def title
        presenter.details? ? "Open the history for #{display_label}" : display_label
      end

      def share
        presenter.share(row)
      end

      def values
        {
          "clicks" => presenter.number(row.clicks),
          "impressions" => presenter.number(row.impressions),
          "ctr" => presenter.percentage(row.ctr),
          "position" => presenter.place(row.position)
        }
      end

      private

      attr_reader :presenter
    end

    attr_reader :query, :result, :tab

    delegate :connected?, to: :result

    def initialize(query:, result:, tab: "queries", details: false)
      @query = query
      @result = result
      @tab = TABS.key?(tab.to_s) ? tab.to_s : TABS.keys.first
      @details = details
    end

    def details?
      @details
    end

    def title
      TITLE
    end

    def stored_only?
      !connected? && rows.any?
    end

    def unconfigured?
      !connected? && empty?
    end

    def disconnected_note
      return nil unless stored_only?

      "Google is not connected, so nothing new is arriving. These are the rows already pulled."
    end

    def problem_note
      return nil if result.problem.blank?

      "Search Console is not syncing, so the newest days may be missing."
    end

    def through_note
      return nil unless result.short?

      "Data runs through #{result.through.strftime("%b %-d")}."
    end

    def frame_id
      details? ? DETAILS_FRAME : FRAME
    end

    def label_column
      TABS.fetch(tab)[:column]
    end

    def queries?
      tab == "queries"
    end

    def trackable?
      details? && queries? && rows.any? { |row| row.label.present? }
    end

    def track_form_id
      ("gsc-track" if trackable?)
    end

    def more_label
      "Show all #{TABS.fetch(tab)[:label].downcase}"
    end

    def columns
      COLUMNS
    end

    def rows
      @rows ||= source_rows.map { |row| Row.new(row: row, presenter: self) }
    end

    def empty?
      rows.empty?
    end

    def tabs
      TABS.map do |key, config|
        AhoyDashboard::MenuOption.new(label: config[:label], value: key,
                                      path: path({ tab: key, view: (DETAILS_VIEW if details?) }.compact),
                                      active: key == tab)
      end
    end

    def keyword_path(row)
      return nil unless tab == "queries" && row.label.present?

      routes.search_console_keyword_path(query.to_query.merge(q: row.label))
    end

    def details_path
      path(tab: tab, view: DETAILS_VIEW)
    end

    def lag_note
      "Search Console data lands two to three days late, so the most recent days are still filling in."
    end

    def coverage_note
      return nil unless result.coverage.measurable?
      return nil if result.coverage.complete?

      counted = percentage(result.coverage.click_share)
      missing = number(result.coverage.missing_clicks)

      "These rows account for #{counted} of the clicks in this range, so #{missing} clicks have no query " \
        "against them. Two things cause that: Google hides searches that were rare or that look " \
        "personal, and it only sends the ones with the most clicks, so the rest of the list is cut " \
        "off. The totals are right; the list underneath them is always short."
    end

    def share(row)
      largest = rows_source_max

      return 0.0 unless largest.positive?

      (row.clicks.to_f / largest).clamp(0.0, 1.0)
    end

    def as_json(*)
      {
        tab: tab,
        connected: connected?,
        details: details?,
        columns: COLUMNS,
        totals: result.totals.to_h,
        coverage: result.coverage.to_h,
        rows: rows.map { |row| { label: row.display_label, share: row.share, values: row.values } }
      }
    end

    def tracking_phrases
      queries? ? rows.map(&:label) : []
    end

    private

    def source_rows
      tab == "pages" ? result.pages : result.queries
    end

    def rows_source_max
      @rows_source_max ||= source_rows.map { |row| row.clicks.to_f }.max.to_f
    end

    def path(overrides)
      routes.search_console_path(query.to_query.merge(overrides))
    end

    def routes
      AhoyDashboard::Engine.routes.url_helpers
    end
  end
end
