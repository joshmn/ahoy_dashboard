module AhoyDashboard
  # The search queries card, or the same card blown up into the details modal.
  #
  # It carries a coverage line the other cards have no equivalent for, because
  # this is the one card whose rows are known not to add up to its own total.
  # Google withholds queries that are rare or look personal and truncates the
  # tail, so the honest thing is to print the gap rather than let somebody sum the
  # column and believe it.
  class SearchConsolePresenter
    FRAME = "report_search_console".freeze
    DETAILS_FRAME = "report_details_search_console".freeze
    DETAILS_VIEW = "details".freeze

    # The card is titled separately from its tabs, so the header does not read
    # "Search queries" beside an active tab reading "Search queries".
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

    Option = Data.define(:label, :value, :path, :active) do
      def active?
        active
      end
    end

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

      def raw_values
        [ row.clicks, row.impressions, row.ctr, row.position ]
      end

      private

      attr_reader :presenter
    end

    attr_reader :query, :result, :tab

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

    # Disconnecting revokes the token; it does not delete what was already
    # pulled, and the settings screen says so. So a disconnected account with
    # history still shows it, and says why it has stopped moving. Hiding those
    # rows would contradict the promise made on the other screen.
    def stored_only?
      !connected? && rows.any?
    end

    # The one state with nothing to show and nothing on the way. Every other
    # state has either rows or a live connection that might produce some, so this
    # is what the three partials gate their empty state and their setup link on.
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

    # Only a query can be tracked, and only a list with one in it is worth
    # hanging a batch form off. The card is nine rows and a glance, with the
    # button under them that opens the whole list, so the boxes go there and the
    # card keeps its width for the labels.
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

    def connected?
      result.connected?
    end

    def rows
      @rows ||= source_rows.map { |row| Row.new(row: row, presenter: self) }
    end

    def empty?
      rows.empty?
    end

    def tabs
      TABS.map do |key, config|
        Option.new(label: config[:label], value: key, path: path(tab: key), active: key == tab)
      end
    end

    # A keyword has a history of its own to open. A page does not: the series
    # behind it is stored at the query grain, so only the queries tab links.
    def keyword_path(row)
      return nil unless tab == "queries" && row.label.present?

      routes.search_console_keyword_path(query.to_query.merge(q: row.label))
    end

    def card_path
      path(tab: tab)
    end

    def details_path
      path(tab: tab, view: DETAILS_VIEW)
    end

    def header_row
      [ label_column, *COLUMNS.map { |column| column[:label] } ]
    end

    # Google's numbers land two to three days late, so a range that ends today is
    # always short at the end and saying so costs one line.
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

    def number(value)
      ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end

    # A fraction on the way in. Google reports ctr as a proportion, not a percent,
    # and printing 0.03 as "0%" was the first thing this got wrong.
    def percentage(value)
      "#{(value.to_f * 100).round(1)}%"
    end

    def place(value)
      value.to_f.round(1)
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
