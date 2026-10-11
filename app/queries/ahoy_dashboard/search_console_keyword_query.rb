module AhoyDashboard
  # One keyword's history: a day at a time, what the range adds up to, the same
  # length of time before it, and the pages it landed on.
  #
  # Read from SearchConsoleKeyword rather than SearchConsoleRow, for the reasons
  # on that model. The window is trimmed to the days the keyword grain was
  # actually pulled for, because a day nobody asked Google about is not a day
  # with no impressions and a chart cannot say the difference.
  class SearchConsoleKeywordQuery
    DEFAULT_PAGES = 10
    MAX_PAGES = 50

    SUM_CLICKS = Arel.sql("sum(clicks)").freeze
    SUM_IMPRESSIONS = Arel.sql("sum(impressions)").freeze
    SUM_POSITION = Arel.sql("sum(position * impressions)").freeze
    EXTENT = Arel.sql("min(date), max(date)").freeze

    Day = Data.define(:date, :clicks, :impressions, :ctr, :position, :recorded) do
      def recorded?
        recorded
      end
    end

    Page = Data.define(:page, :clicks, :impressions, :ctr, :position)

    Stored = Data.define(:clicks, :impressions, :ctr, :position)

    Totals = Data.define(:clicks, :impressions, :ctr, :position) do
      def any?
        clicks.positive? || impressions.positive?
      end
    end

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

      first, last = Array(SearchConsoleKeyword.pick(EXTENT))

      @covered = first && (first..last)
    end

    def window
      return @window if defined?(@window)

      @window = overlap(requested, covered)
    end

    # Measured off the window rather than the range asked for, so a thirty day
    # view whose last three days have not landed is not held against a full
    # thirty. Offered only when the whole of it was pulled: half a window
    # against a whole one reads as a fall that never happened.
    def previous_window
      return @previous_window if defined?(@previous_window)

      @previous_window = begin
        if window.nil? || covered.nil?
          nil
        else
          length = (window.end - window.begin).to_i + 1
          candidate = (window.begin - length)..(window.begin - 1)

          candidate if candidate.begin >= covered.begin
        end
      end
    end

    def overlap(one, other)
      return nil if one.nil? || other.nil?

      first = [ one.begin, other.begin ].max
      last = [ one.end, other.end ].min

      first <= last ? first..last : nil
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
          clicks = clicks.to_i
          impressions = impressions.to_i

          [ date, Stored.new(clicks: clicks, impressions: impressions, ctr: ratio(clicks, impressions),
                             position: average_position(weight.to_f, impressions)) ]
        end.to_h
    end

    def daily_rows
      @daily_rows ||= slice.apply(SearchConsoleKeyword.where(query: keyword, date: window))
        .group(:date).pluck(:date, SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION)
    end

    def totals_for(dates)
      return Totals.new(clicks: 0, impressions: 0, ctr: 0.0, position: 0.0) if dates.nil?

      clicks, impressions, weight = if dates == window
        [daily_rows.sum { |row| row[1].to_i }, daily_rows.sum { |row| row[2].to_i },
         daily_rows.sum { |row| row[3].to_f }]
      else
        sums(slice.apply(SearchConsoleKeyword.where(query: keyword, date: dates)))
      end

      Totals.new(
        clicks: clicks,
        impressions: impressions,
        ctr: ratio(clicks, impressions),
        position: average_position(weight, impressions)
      )
    end

    def sums(relation)
      row = Array(relation.pick(SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION))

      [ row[0].to_i, row[1].to_i, row[2].to_f ]
    end

    # The page grain, which is a different pull and a shorter one. Read over the
    # range that was asked for rather than the trimmed window, because these rows
    # go back further than the keyword ones do.
    def landing_pages
      slice.apply(SearchConsoleRow.where(query: keyword, date: requested))
        .group(:page)
        .order(SUM_CLICKS => :desc, SUM_IMPRESSIONS => :desc)
        .limit(pages)
        .pluck(:page, SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION)
        .map do |page, clicks, impressions, weight|
          Page.new(
            page: page,
            clicks: clicks.to_i,
            impressions: impressions.to_i,
            ctr: ratio(clicks.to_i, impressions.to_i),
            position: average_position(weight.to_f, impressions.to_i)
          )
        end
    end

    def seen
      return @seen if defined?(@seen)

      first, last = Array(slice.apply(SearchConsoleKeyword.where(query: keyword)).pick(EXTENT))

      @seen = first && (first..last)
    end

    def average_position(weight, impressions)
      impressions.positive? ? (weight / impressions).round(1) : 0.0
    end

    def ratio(part, whole)
      whole.to_i.zero? ? 0.0 : part.to_f / whole
    end
  end
end
