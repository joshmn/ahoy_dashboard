module AhoyDashboard
  # One keyword's page: the four figures, the series behind whichever one is
  # selected, the days it was recorded on and the pages it landed on.
  #
  # Position runs the other way from everything else on the dashboard, so a fall
  # in the number is an improvement and the change reads as better or worse
  # rather than up or down. Click through and position also move in units nobody
  # wants a percentage of, so those changes are printed as the distance moved.
  class SearchConsoleKeywordPresenter
    DEFAULT_SERIES = "clicks".freeze

    # short is what a column heading calls it. The long label names the measure
    # where there is room for it; four stats across a dialog is not that, and
    # "Click through rate" wrapping to two lines makes one tile taller than the
    # three beside it.
    SERIES = {
      "clicks" => { label: "Clicks", short: "Clicks", format: :integer, kind: :area },
      "impressions" => { label: "Impressions", short: "Impressions", format: :integer, kind: :area },
      "ctr" => { label: "Click through rate", short: "CTR", format: :rate, kind: :line },
      "position" => { label: "Average position", short: "Position", format: :decimal, kind: :line }
    }.freeze


    Figure = Data.define(:key, :label, :short, :value, :display, :delta, :against, :active, :path) do
      def active?
        active
      end
    end

    Row = Data.define(:date, :clicks, :impressions, :ctr, :position)

    Landing = Data.define(:page, :clicks, :impressions, :ctr, :position, :share)

    attr_reader :query, :result, :series

    def initialize(query:, result:, series: nil, context: SearchConsole::PageContext.new)
      @query = query
      @result = result
      @series = SERIES.key?(series.to_s) ? series.to_s : DEFAULT_SERIES
      @context = context
    end

    def keyword
      result.keyword
    end

    def slice
      result.slice
    end

    def menus
      @menus ||= AhoyDashboard::SearchConsoleSlicePresenter.new(
        slice: slice, countries: context.countries, path: ->(overrides) { path(overrides) }
      )
    end

    def heading
      keyword
    end

    def source_line
      range_label
    end

    def landings_line
      "Landing pages"
    end

    def details_path
      path(view: DETAILS_VIEW)
    end

    DETAILS_VIEW = "details".freeze
    DETAILS_FRAME = "dash_keyword_details".freeze

    def series_label
      SERIES.fetch(series)[:label]
    end

    def empty?
      !result.any?
    end

    def any_pages?
      result.pages.any?
    end

    def summary
      parts = [ window_label ]
      parts << "#{number(result.totals.clicks)} #{"click".pluralize(result.totals.clicks)}"
      parts << "#{number(result.totals.impressions)} #{"impression".pluralize(result.totals.impressions)}"

      parts.join(" · ")
    end

    # The period's own name where it has one, and the dates only for a custom
    # range. Lower-casing "Jul 17 to Aug 15" turned the month into "aug".
    def range_label
      query.period.custom? ? query.range_label : query.period.label
    end

    def window_label
      return range_label if result.window.nil?

      first = result.window.begin
      last = result.window.end

      return first.strftime("%b %-d, %Y") if first == last

      "#{first.strftime("%b %-d, %Y")} to #{last.strftime("%b %-d, %Y")}"
    end

    def figures
      SERIES.map do |key, config|
        current = value_for(result.totals, key)
        change = change_for(key)

        Figure.new(
          key: key,
          label: config[:label],
          short: config[:short],
          value: current,
          display: display(key, current),
          delta: change,
          against: change && display(key, value_for(result.previous, key)),
          active: key == series,
          path: path(series: (key unless key == DEFAULT_SERIES))
        )
      end
    end

    def rows
      result.recorded_days.reverse.map do |day|
        Row.new(
          date: day.date,
          clicks: number(day.clicks),
          impressions: number(day.impressions),
          ctr: percentage(day.ctr),
          position: place(day.position)
        )
      end
    end

    # share is the page's cut of what the pages add up to, not of the keyword's
    # own clicks. Those two are different numbers on purpose: Google withholds
    # far more at query by page than at query alone, so the pages never account
    # for the whole keyword and a share against the keyword would read as pages
    # going missing rather than as Google withholding them.
    def landings
      counted = result.pages.sum(&:clicks)

      result.pages.map do |page|
        Landing.new(
          page: page.page,
          clicks: number(page.clicks),
          impressions: number(page.impressions),
          ctr: percentage(page.ctr),
          position: place(page.position),
          share: counted.positive? ? percentage(page.clicks.to_f / counted) : nil
        )
      end
    end

    # The sparkline's numbers, in order. A day the keyword grain was never pulled
    # for is not a day with no impressions, so it is left out rather than drawn
    # as a zero: a gap in the pull would otherwise read as the keyword dying.
    def spark_values
      result.recorded_days.map { |day| point_value(day).to_f }
    end

    def chart_kind
      SERIES.fetch(series)[:kind]
    end

    def chart_data
      return [] if result.days.empty?

      [ { name: series_label, data: points } ]
    end

    def chart_options
      {
        library: {
          plugins: { tmFormat: { label: series_label, value: format_type.to_s, interval: "day" } },
          scales: { y: { reverse: series == "position" } }
        }
      }
    end

    def period_options
      AhoyDashboard::SeoRange.periods.map do |period|
        {
          label: period.label,
          url: link_for(query.with(period: period.key).to_query),
          active: period.key == query.period.key
        }
      end
    end

    def connection_path
      routes.settings_google_connection_path
    end

    def rows_path
      routes.settings_search_console_rows_path(q: keyword)
    end

    def lag_note
      "Search Console data lands two to three days late, so the last few days are still filling in."
    end

    def trim_note
      return nil unless result.trimmed?
      return nothing_pulled_note if result.window.nil?

      "You asked for #{range_label.downcase}. The keyword record runs #{covered_label}, so the chart " \
        "covers #{window_label} and stops there. The days outside that were never pulled at this grain, " \
        "which is not the same as days this keyword got nothing."
    end

    def gap_note
      return nil if empty?

      quiet = result.days.count { |day| !day.recorded? }
      return nil if quiet.zero?

      "Google named this keyword on #{result.recorded_days.size} of the #{result.days.size} days in the " \
        "chart. On the other #{quiet} it said nothing, which usually means too few impressions to report."
    end

    def seen_note
      return nil if result.seen.nil?

      "First recorded #{result.seen.begin.strftime("%b %-d, %Y")}, last seen " \
        "#{result.seen.end.strftime("%b %-d, %Y")}."
    end

    def comparison_note
      return nil unless result.comparable?

      "Compared against #{result.previous_window.begin.strftime("%b %-d")} to " \
        "#{result.previous_window.end.strftime("%b %-d, %Y")}, the same length of time before this one."
    end

    def pages_note
      "Google holds back more data for each page. They add up to less than the clicks above, and that is normal."
    end

    def empty_state
      if result.covered.nil? && !context.connected?
        return AhoyDashboard::SetupNotice.search_console(routes, account: context.account)
      end

      { title: empty_title, hint: empty_hint, action: empty_action }
    end

    def empty_action
      if slice.any?
        return { label: "Show all devices and countries", url: path(device: nil, country: nil),
                 data: { tm_frame: "_top" }, primary: true }
      end

      { label: "Search Console settings", url: connection_path, data: { tm_frame: "_top" }, primary: false }
    end

    def empty_title
      return "Nothing pulled at the keyword grain yet" if result.covered.nil?

      "Nothing recorded for this keyword in this range"
    end

    def empty_hint
      return "Search Console data syncs every night once Google is connected." if result.covered.nil?
      return "#{seen_note} Try a wider date range." if result.seen.present?
      return slice.empty_hint if slice.any?

      "Google never named this keyword on a day it was asked about. #{lag_note}"
    end

    def as_json(*)
      {
        keyword: keyword,
        series: series,
        device: slice.device,
        country: slice.country,
        window: { from: result.window&.begin, to: result.window&.end },
        totals: result.totals.to_h,
        previous: (result.previous.to_h if result.comparable?),
        days: result.recorded_days.map(&:to_h),
        pages: result.pages.map(&:to_h),
        options: chart_options,
        url: path
      }
    end

    def path(overrides = {})
      link_for(query.to_query.merge(overrides))
    end

    def tracking_phrases
      [keyword]
    end

    private

    attr_reader :context

    def link_for(params)
      params = { series: series_param, **slice.to_h }.merge(params)

      routes.search_console_keyword_path(params.merge(q: keyword).compact)
    end

    def series_param
      (series unless series == DEFAULT_SERIES)
    end

    def format_type
      SERIES.fetch(series)[:format]
    end

    def points
      result.days.map do |day|
        [ stamp(day.date), point_value(day) ]
      end
    end

    def point_value(day)
      case series
      when "impressions" then day.impressions
      when "ctr" then day.ctr && (day.ctr * 100).round(2)
      when "position" then day.position&.round(1)
      else day.clicks
      end
    end

    def stamp(date)
      (@time_zone ||= AhoyDashboard.time_zone).local(date.year, date.month, date.day)
    end

    def value_for(totals, key)
      case key
      when "impressions" then totals.impressions
      when "ctr" then totals.ctr
      when "position" then totals.position
      else totals.clicks
      end
    end

    def display(key, value)
      case key
      when "ctr" then percentage(value)
      when "position" then place(value)
      else number(value)
      end
    end

    # Counts move by proportion, click through by percentage points, and
    # position by places. Printing a percentage change in an average position
    # would be a number about a number.
    def change_for(key)
      return nil unless result.comparable?

      current = value_for(result.totals, key)
      before = value_for(result.previous, key)

      case key
      when "ctr" then points_change(current, before)
      when "position" then places_change(current, before)
      else percent_change(current, before)
      end
    end

    def percent_change(current, before)
      return nil unless before.to_f.positive?

      moved = ((current - before) / before.to_f * 100).round(1)

      AhoyDashboard::Delta.build("#{moved.abs}%", moved)
    end

    def points_change(current, before)
      moved = ((current - before) * 100).round(1)

      AhoyDashboard::Delta.build("#{moved.abs} pts", moved)
    end

    def places_change(current, before)
      return nil unless before.to_f.positive?

      moved = (current - before).round(1)

      AhoyDashboard::Delta.build(moved.abs.to_s, moved, inverted: true)
    end

    def covered_label
      "#{result.covered.begin.strftime("%b %-d, %Y")} to #{result.covered.end.strftime("%b %-d, %Y")}"
    end

    def nothing_pulled_note
      return "Nothing has been pulled at the keyword grain yet." if result.covered.nil?

      "The keyword record runs #{covered_label}, and none of that is inside #{range_label.downcase}."
    end

    def number(value)
      ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end

    def percentage(value)
      "#{(value.to_f * 100).round(1)}%"
    end

    def place(value)
      value.to_f.round(1)
    end

    def routes
      AhoyDashboard::Engine.routes.url_helpers
    end
  end
end
