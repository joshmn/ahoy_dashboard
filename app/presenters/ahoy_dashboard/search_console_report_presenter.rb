module AhoyDashboard
  class SearchConsoleReportPresenter
    include AhoyDashboard::Seo::Exportable
    include AhoyDashboard::Seo::Formatting

    SURFACE = AhoyDashboard::Seo::Surface.find("search_console")

    TOP = AhoyDashboard::SetupNotice::TOP

    CLICKS = "clicks".freeze
    IMPRESSIONS = "impressions".freeze
    CTR = "ctr".freeze
    POSITION = "position".freeze

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

    DELTA_KINDS = { number: :percent, percent: :points, place: :places }.freeze

    STROKES = { POSITION => "#d8c08a" }.freeze

    CHART_FORMATS = { CLICKS => "integer", IMPRESSIONS => "integer", CTR => "rate", POSITION => "decimal" }.freeze

    ROWS_NOTE = "Google reports two to three days late, and query and page rows add up to less than these totals " \
                "because Google leaves out rare searches.".freeze

    UNSLICED_NOTE = "Clicks and impressions are Google's totals for the property. #{ROWS_NOTE}".freeze

    SLICED_NOTE = "Days stored before device and country were pulled have neither, so they are left out here. " \
                  "Google reports two to three days late, and it leaves out more searches the finer you cut, " \
                  "so the rows add up to less than these totals.".freeze

    Tile = Data.define(:measure, :display, :delta) do
      def key
        measure.key
      end

      def label
        measure.short
      end
    end

    class << self
      def data_note(through:, slice:, sliced: SLICED_NOTE)
        lead = through ? "Data runs through #{through}. " : ""
        return "#{lead}#{UNSLICED_NOTE}" unless slice&.any?

        "#{lead}Showing #{slice.label} only. #{sliced}"
      end
    end

    attr_reader :query, :result, :measure

    delegate :connected?, :any?, :rows, :rows?, :term, :tab, :slice, to: :result

    def initialize(query:, result:, measure: nil, context: SearchConsole::PageContext.new)
      @query = query
      @result = result
      @measure = MEASURES.find { |candidate| candidate.key == measure.to_s } || MEASURES.first
      @context = context
    end

    def title
      SURFACE.title
    end

    def blurb
      SURFACE.blurb
    end

    def queries?
      tab == AhoyDashboard::SearchConsoleReportQuery::QUERIES
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

      "vs #{on_label(window.begin)} to #{on_label(window.end)}"
    end

    def tabs
      AhoyDashboard::SearchConsoleReportQuery::TABS.map do |key|
        AhoyDashboard::MenuOption.new(key.capitalize, key, path(tab: key, q: nil), key == tab)
      end
    end

    def period_options
      AhoyDashboard::Seo::Periods.menu(query, custom: false) { |period| path(period: period.key) }
    end

    def data_note
      self.class.data_note(through: last_date, slice: slice)
    end

    def rows_caption
      counted = rows.size
      noun = queries? ? "query" : "page"

      "#{counted} #{noun.pluralize(counted)}"
    end

    def trend?(row)
      row.trend? && row.trend.any?(&:positive?)
    end

    def range_label
      query.range_title
    end

    def last_date
      on_label(result.last_date)
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
      if slice.any?
        return { title: "No Search Console data in this range", hint: slice.empty_hint,
                 action: menus.clear_action(data: TOP) }
      end

      AhoyDashboard::Seo::SearchConsoleEmptyState.call(
        query: query, context: context, routes: routes, path: ->(overrides) { path(overrides) },
        title: "No Search Console data in this range",
        hint: "Google reports two to three days late, and new data syncs every night. Try a longer date range."
      )
    end

    def setup_notice
      AhoyDashboard::SetupNotice.search_console(routes, account: context.account)
    end

    def sync_reason
      AhoyDashboard::SearchConsole.sync_refusal(context.account)
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

    def place(value)
      super.to_s
    end

    def export_key
      SURFACE.export
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
          queries? ? [] : rows.map { |row| csv_row(AhoyDashboard::Seo::Formatting.url_path(row.label), row) }
        end
      ]
    end

    def tracking_phrases
      queries? ? rows.map(&:label) : []
    end

    private

    attr_reader :context

    def query_csv_label(row)
      row.label.presence || AhoyDashboard::SearchConsole::ANONYMIZED_QUERY
    end

    def csv_row(label, row)
      [ label, row.clicks, row.impressions, csv_percent(row.ctr), row.position&.to_f&.round(1) ]
    end

    def value_of(source, measure)
      source.public_send(measure.key)
    end

    def delta_for(measure)
      return nil unless result.comparable? && result.previous.impressions.positive?
      return nil if measure.format != :number && !result.totals.impressions.positive?

      kind = DELTA_KINDS.fetch(measure.format)

      AhoyDashboard::Delta.between(kind, now: value_of(result.totals, measure), before: value_of(result.previous, measure),
                                         places: kind == :percent ? 0 : 1, hide_zero: true)
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

    def routes
      AhoyDashboard::Engine.routes.url_helpers
    end
  end
end
