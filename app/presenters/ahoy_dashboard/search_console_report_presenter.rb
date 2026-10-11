module AhoyDashboard
  # The Search Console page: four numbers, a chart of one of them, and the rows
  # underneath.
  #
  # The three tables disagree with each other on purpose, so the page says once,
  # under the chart, that the rows come up short of the totals.
  class SearchConsoleReportPresenter
    include AhoyDashboard::Seo::Exportable

    TITLE = "Performance".freeze
    SUBTITLE = "Clicks, impressions, CTR and position from Google Search Console.".freeze

    CLICKS = "clicks".freeze
    IMPRESSIONS = "impressions".freeze
    CTR = "ctr".freeze
    POSITION = "position".freeze

    # Position counts the wrong way round: one is the best a page can do, so a
    # fall is an improvement and the arrow has to be read the other way. inverted
    # is the only thing that says so, and every delta on this page reads it.
    Measure = Data.define(:key, :label, :short, :caption, :inverted, :format) do
      def inverted?
        inverted
      end
    end

    MEASURES = [
      Measure.new(CLICKS, "Clicks", "Clicks", "Daily clicks", false, :number),
      Measure.new(IMPRESSIONS, "Impressions", "Impressions", "Daily impressions", false, :number),
      Measure.new(CTR, "CTR", "CTR", "Daily click through rate", false, :percent),
      Measure.new(POSITION, "Position", "Avg position", "Daily avg position", true, :place)
    ].freeze

    # The line the design draws for each. Position is the odd one out and looks
    # it: a banded axis running the wrong way is not the same kind of picture as
    # a count rising off zero, and colouring it the same would say it was.
    STROKES = { POSITION => "#d8c08a" }.freeze

    CHART_FORMATS = { CLICKS => "integer", IMPRESSIONS => "integer", CTR => "rate", POSITION => "decimal" }.freeze

    UNSLICED_NOTE = "Clicks and impressions are Google's totals for the property. Google reports two to three " \
                    "days late, and query and page rows add up to less than these totals because Google leaves " \
                    "out rare searches.".freeze

    SLICED_LAG_NOTE = "Google reports two to three days late, and it leaves out more searches the finer you cut, " \
                      "so the rows add up to less than these totals.".freeze

    Tile = Data.define(:measure, :display, :delta) do
      def key
        measure.key
      end

      def label
        measure.short
      end
    end

    Option = Data.define(:label, :value, :path, :active) do
      def active?
        active
      end
    end

    attr_reader :query, :result, :measure

    def initialize(query:, result:, measure: nil, context: SearchConsole::PageContext.new,
      routes: AhoyDashboard::Engine.routes.url_helpers)
      @query = query
      @result = result
      @measure = MEASURES.find { |candidate| candidate.key == measure.to_s } || MEASURES.first
      @routes = routes
      @context = context
    end

    def title
      TITLE
    end

    def subtitle
      SUBTITLE
    end

    def connected?
      result.connected?
    end

    def any?
      result.any?
    end

    def rows
      result.rows
    end

    def rows?
      result.rows?
    end

    def term
      result.term
    end

    def tab
      result.tab
    end

    def queries?
      tab == AhoyDashboard::SearchConsoleReportQuery::QUERIES
    end

    def slice
      result.slice
    end

    def menus
      @menus ||= AhoyDashboard::SearchConsoleSlicePresenter.new(
        slice: slice, countries: context.countries, path: ->(overrides) { path(overrides) }
      )
    end

    def tiles
      MEASURES.map do |candidate|
        Tile.new(candidate, format(candidate, value_of(result.totals, candidate)), delta_for(candidate))
      end
    end

    def comparison_title
      return nil unless result.comparable?

      window = result.previous_window

      "vs #{AhoyDashboard::SeoHelper.short_date(window.begin)} to #{AhoyDashboard::SeoHelper.short_date(window.end)}"
    end

    def measures
      MEASURES.map do |candidate|
        Option.new(candidate.label, candidate.key, path(measure: candidate.key), candidate == self.measure)
      end
    end

    def tabs
      AhoyDashboard::SearchConsoleReportQuery::TABS.map do |key|
        Option.new(key.capitalize, key, path(tab: key, q: nil), key == tab)
      end
    end

    # Says where the chart stops, because Google lands two to three days late
    # and a line that ran to today would show a cliff that is not there.
    def data_note
      through = last_date ? "Data runs through #{last_date}. " : ""
      return "#{through}#{UNSLICED_NOTE}" unless slice.any?

      "#{through}Showing #{slice.label} only. Days stored before device and country were pulled have " \
        "neither, so they are left out here. #{SLICED_LAG_NOTE}"
    end

    def rows_caption
      counted = rows.size
      noun = queries? ? "query" : "page"

      "#{counted} #{noun.pluralize(counted)}"
    end

    def trend?(row)
      row.trend? && row.trend.any?(&:positive?)
    end

    # The period's own name where it has one, and the dates only when it does
    # not. Lower-casing the label was turning "Jul 17 to Aug 15" into "aug".
    def range_label
      query.period.custom? ? query.range_label : query.period.label
    end

    def last_date
      return if result.last_date.nil?

      AhoyDashboard::SeoHelper.short_date(result.last_date)
    end

    def chart_data
      [ { name: measure.label, data: result.days.map { |day| [ day.date.to_s, chart_value(day) ] } } ]
    end

    def chart_options
      {
        library: {
          tmFill: !measure.inverted?,
          tmStroke: STROKES[measure.key],
          plugins: {
            tmFormat: { label: measure.label, value: CHART_FORMATS.fetch(measure.key), interval: "day",
                        missing: "No impressions" },
            tmAnnotations: []
          },
          scales: { y: { min: (0.1 if measure.inverted?), reverse: measure.inverted? } }
        }
      }
    end

    def path(overrides = {})
      routes.search_console_report_path(
        query.to_query.merge(measure: measure.key, tab: tab, q: term.presence, **slice.to_h)
          .compact.merge(overrides).compact
      )
    end

    def sync_path
      routes.settings_search_console_sync_path
    end

    def connection_path
      routes.settings_google_connection_path
    end

    def empty_state
      return sliced_empty_state if slice.any?

      AhoyDashboard::Seo::SearchConsoleEmptyState.call(
        query: query, context: context, routes: routes, path: ->(overrides) { path(overrides) },
        title: "No Search Console data in this range",
        hint: "Google reports two to three days late, and new data syncs every night. Try a longer date range."
      )
    end

    def sliced_empty_state
      { title: "No Search Console data in this range", hint: slice.empty_hint,
        action: { label: "Show all devices and countries", url: path(device: nil, country: nil),
                  data: { tm_frame: "_top" }, primary: true } }
    end

    def setup_notice
      AhoyDashboard::SetupNotice.search_console(routes, account: context.account)
    end

    def sync_reason
      return AhoyDashboard::SearchConsole.unavailable_reason unless AhoyDashboard::SearchConsole.enabled?
      return "Connect Google first." unless context.account && context.account.connected?

      "Pick a property first." unless context.account.property_selected?
    end

    def sync_fix
      sync_reason && { label: "Google settings", url: connection_path }
    end

    def keyword_path(label)
      routes.search_console_keyword_path(query.to_query.merge(slice.to_query).merge(q: label))
    end

    def keyword_details_path(label)
      routes.search_console_keyword_path(
        query.to_query.merge(slice.to_query).merge(q: label, view: AhoyDashboard::SearchConsoleKeywordPresenter::DETAILS_VIEW)
      )
    end

    def format(measure, value)
      case measure.format
      when :percent then percentage(value)
      when :place then place(value)
      else AhoyDashboard::CompactNumber.call(value)
      end
    end

    def number(value)
      ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end

    # A fraction on the way in. Google reports ctr as a proportion, not a
    # percent, and printing 0.03 as "0%" was the first thing this got wrong.
    def percentage(value)
      "#{(value.to_f * 100).round(1)}%"
    end

    def place(value)
      value.to_f.round(1).to_s
    end

    def export_key
      AhoyDashboard::Seo::Surface.find("search_console").export
    end

    def export_path(params)
      routes.search_console_report_path(params)
    end

    def export_params
      query.to_query.merge(measure: measure.key, tab: tab, q: term.presence, **slice.to_h).compact
    end

    def csv_tables
      [
        AhoyDashboard::Seo::CsvTable.new(key: AhoyDashboard::SearchConsoleReportQuery::QUERIES, label: "Queries",
                                         headers: [ "Query", "Clicks", "Impressions", "CTR", "Position" ]) do
          queries? ? rows.map { |row| csv_row(query_csv_label(row), row) } : []
        end,
        AhoyDashboard::Seo::CsvTable.new(key: AhoyDashboard::SearchConsoleReportQuery::PAGES, label: "Pages",
                                         headers: [ "Page", "Clicks", "Impressions", "CTR", "Position" ]) do
          queries? ? [] : rows.map { |row| csv_row(url_csv(row.label), row) }
        end
      ]
    end

    def tracking_phrases
      queries? ? rows.map(&:label) : []
    end

    private

    def query_csv_label(row)
      row.label.presence || AhoyDashboard::SearchConsole::ANONYMIZED_QUERY
    end

    def csv_row(label, row)
      [ label, row.clicks, row.impressions, csv_percent(row.ctr), row.position&.to_f&.round(1) ]
    end

    def url_csv(url)
      return nil if url.blank?

      url.to_s.sub(%r{\Ahttps?://[^/]+}, "").presence || "/"
    end

    attr_reader :routes, :context

    def value_of(source, measure)
      source.public_send(measure.key)
    end

    def delta_for(measure)
      return nil unless result.comparable? && result.previous.impressions.positive?

      before = value_of(result.previous, measure).to_f
      now = value_of(result.totals, measure).to_f

      return nil if measure.format != :number && !result.totals.impressions.positive?

      case measure.format
      when :percent
        moved = ((now - before) * 100).round(1)
        delta("#{moved.abs} pts", moved)
      when :place
        moved = (now - before).round(1)
        delta(moved.abs.to_s, moved, inverted: true)
      else
        return nil if before.zero?

        moved = ((now - before) / before * 100).round
        delta("#{moved.abs}%", moved)
      end
    end

    def delta(text, moved, inverted: false)
      return nil if moved.zero?

      AhoyDashboard::Delta.build(text, moved, inverted: inverted)
    end

    def chart_value(day)
      value = value_of(day, measure)
      return nil if [ CTR, POSITION ].include?(measure.key) && day.impressions.to_i.zero?

      case measure.key
      when CTR then (value.to_f * 100).round(2)
      when POSITION then value.to_f.round(2)
      else value
      end
    end
  end
end
