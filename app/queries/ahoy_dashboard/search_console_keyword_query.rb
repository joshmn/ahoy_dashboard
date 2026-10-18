module AhoyDashboard
  class SearchConsoleKeywordQuery
    DEFAULT_PAGES = 10
    MAX_PAGES = 50

    Day = Data.define(:date, :clicks, :impressions, :ctr, :position, :recorded) do
      def recorded?
        recorded
      end
    end

    Page = Data.define(:page, :clicks, :impressions, :ctr, :position)

    Result = Data.define(
      :keyword, :slice, :requested, :window, :days, :totals, :previous, :previous_window, :pages, :seen, :covered
    ) do
      def any?
        days.any?(&:recorded?)
      end

      def recorded_days
        days.select(&:recorded?)
      end

      def comparable?
        previous_window.present? && previous.any?
      end

      def trimmed?
        window != requested
      end
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(keyword:, range:, pages: DEFAULT_PAGES, slice: SearchConsole::Slice.new)
      @keyword = keyword.to_s
      @slice = slice
      @range = range
      @pages = pages.to_i.clamp(1, MAX_PAGES)
    end

    def call
      Result.new(
        keyword: keyword,
        slice: slice,
        requested: requested,
        window: window,
        days: days,
        totals: totals_for(window),
        previous: totals_for(previous_window),
        previous_window: previous_window,
        pages: landing_pages,
        seen: seen,
        covered: covered
      )
    end

    private

    attr_reader :keyword, :range, :pages, :slice

    def requested
      @requested ||= range.begin.to_date..range.end.to_date
    end

    def covered
      return @covered if defined?(@covered)

      @covered = SearchConsole::Sums.extent(SearchConsoleKeyword.all)
    end

    def windows
      @windows ||= SearchConsole::ComparedWindow.within(requested: requested, covered: covered)
    end

    def window
      windows.current
    end

    def previous_window
      windows.previous
    end

    def days
      return [] if window.nil?

      stored = rows_by_date

      window.map do |date|
        row = stored[date]

        if row.nil?
          Day.new(date: date, clicks: 0, impressions: 0, ctr: nil, position: nil, recorded: false)
        else
          Day.new(date: date, clicks: row.clicks, impressions: row.impressions,
                  ctr: row.ctr, position: row.position, recorded: true)
        end
      end
    end

    def rows_by_date
      @rows_by_date ||= daily_rows.map do |date, clicks, impressions, weight|
          [ date, totals_of(clicks, impressions, weight) ]
        end.to_h
    end

    def daily_rows
      @daily_rows ||= slice.apply(SearchConsoleKeyword.where(query: keyword, date: window))
        .group(:date).pluck(:date, *SearchConsole::Sums::ALL)
    end

    def totals_for(dates)
      return totals_of(0, 0, 0) if dates.nil?
      return totals_of(*SearchConsole::Sums.add(daily_rows)) if dates == window

      totals_of(*SearchConsole::Sums.pick(slice.apply(SearchConsoleKeyword.where(query: keyword, date: dates))))
    end

    def landing_pages
      slice.apply(SearchConsoleRow.where(query: keyword, date: requested))
        .group(:page)
        .order(SearchConsole::Sums::CLICKS => :desc, SearchConsole::Sums::IMPRESSIONS => :desc)
        .limit(pages)
        .pluck(:page, *SearchConsole::Sums::ALL)
        .map do |page, clicks, impressions, weight|
          reading = totals_of(clicks, impressions, weight)

          Page.new(page: page, clicks: reading.clicks, impressions: reading.impressions, ctr: reading.ctr,
                   position: reading.position)
        end
    end

    def seen
      return @seen if defined?(@seen)

      @seen = SearchConsole::Sums.extent(slice.apply(SearchConsoleKeyword.where(query: keyword)))
    end

    def totals_of(clicks, impressions, weight)
      SearchConsole::Totals.from(clicks: clicks, impressions: impressions, weight: weight, places: 1)
    end
  end
end
