module AhoyDashboard
  class SearchConsoleKeywordPresenter
    include AhoyDashboard::Seo::Formatting

    DEFAULT_SERIES = "clicks".freeze

    DELTA_KINDS = { "ctr" => :points, "position" => :places }.freeze

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

    delegate :keyword, :slice, to: :result

    def initialize(query:, result:, series: nil, context: SearchConsole::PageContext.new)
      @query = query
      @result = result
      @series = SERIES.key?(series.to_s) ? series.to_s : DEFAULT_SERIES
      @context = context
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

    def range_label
      query.range_title
    end

    def window_label
      return range_label if result.window.nil?

      first = result.window.begin
      last = result.window.end

      return long_date(first) if first == last

      "#{long_date(first)} to #{long_date(last)}"
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

    def spark_values
      result.recorded_days.map { |day| point_value(day).to_f }
    end

    def chart_data
      return [] if result.days.empty?

      [ { name: series_label, data: points } ]
    end

    def chart_options
      {
        library: {
          tmFill: SERIES.fetch(series)[:kind] == :area,
          plugins: { tmFormat: { label: series_label, value: format_type.to_s, interval: "day" } },
          scales: { y: { reverse: series == "position" } }
        }
      }
    end

    def period_options
      AhoyDashboard::Seo::Periods.menu(query) { |period| link_for(query.with(period: period.key).to_query) }
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

      "First recorded #{long_date(result.seen.begin)}, last seen #{long_date(result.seen.end)}."
    end

    def comparison_note
      return nil unless result.comparable?

      "Compared against #{result.previous_window.begin.strftime(AhoyDashboard::DateFormat::SHORT)} to " \
        "#{long_date(result.previous_window.end)}, the same length of time before this one."
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
      return menus.clear_action(data: AhoyDashboard::SetupNotice::TOP) if slice.any?

      AhoyDashboard::Seo::SearchConsoleEmptyState.settings_action(routes)
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
      time_zone.local(date.year, date.month, date.day)
    end

    def long_date(date)
      date.strftime(AhoyDashboard::DateFormat::LONG)
    end

    def value_for(totals, key)
      totals.public_send(key)
    end

    def display(key, value)
      case key
      when "ctr" then percentage(value)
      when "position" then place(value)
      else number(value)
      end
    end

    def change_for(key)
      return nil unless result.comparable?

      AhoyDashboard::Delta.between(DELTA_KINDS.fetch(key, :percent), now: value_for(result.totals, key),
                                   before: value_for(result.previous, key), require_before: key == "position")
    end

    def covered_label
      "#{long_date(result.covered.begin)} to #{long_date(result.covered.end)}"
    end

    def nothing_pulled_note
      return "Nothing has been pulled at the keyword grain yet." if result.covered.nil?

      "The keyword record runs #{covered_label}, and none of that is inside #{range_label.downcase}."
    end

    def routes
      AhoyDashboard::Engine.routes.url_helpers
    end
  end
end
