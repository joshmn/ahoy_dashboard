module AhoyDashboard
  class SearchConsoleReportQuery
    DEFAULT_ROWS = 25
    MAX_ROWS = 200
    TREND_DAYS = 28

    Row = Data.define(:label, :clicks, :impressions, :ctr, :position, :trend) do
      def trend?
        trend.present? && trend.size > 1
      end
    end

    Day = Data.define(:date, :clicks, :impressions, :ctr, :position)

    Result = Data.define(:range, :tab, :term, :slice, :days, :totals, :previous, :previous_window, :rows,
                         :last_date, :connected) do
      def connected?
        connected
      end

      def comparable?
        previous_window.present?
      end

      def any?
        days.any?
      end

      def rows?
        rows.any?
      end
    end

    QUERIES = "queries".freeze
    PAGES = "pages".freeze
    TABS = [ QUERIES, PAGES ].freeze

    def self.call(**options)
      new(**options).call
    end

    def initialize(range:, tab: QUERIES, term: nil, rows: DEFAULT_ROWS, account: nil,
                   slice: AhoyDashboard::SearchConsole::Slice.new)
      @range = range
      @slice = slice
      @tab = TABS.include?(tab.to_s) ? tab.to_s : QUERIES
      @term = term.to_s.strip
      @limit = rows.to_i.clamp(1, MAX_ROWS)
      @account = account || AhoyDashboard::GoogleAccount.current
    end

    def call
      Result.new(
        range: range,
        tab: tab,
        term: term,
        slice: slice,
        days: days,
        totals: totals_of(*SearchConsole::Sums.add(daily_rows)),
        previous: totals_for(windows.previous),
        previous_window: windows.previous,
        rows: rows,
        last_date: last_date,
        connected: account.present? && account.ready?
      )
    end

    private

    attr_reader :range, :tab, :term, :limit, :account, :slice

    def queries?
      tab == QUERIES
    end

    def days
      @days ||= daily_rows.map do |on, clicks, impressions, weight|
          totals = totals_of(clicks, impressions, weight)

          Day.new(on, totals.clicks, totals.impressions, totals.ctr, totals.position)
        end
    end

    def daily_rows
      @daily_rows ||= sliced(AhoyDashboard::SearchConsoleTotal.in_range(range))
        .group(:date).order(:date).pluck(:date, *SearchConsole::Sums::ALL)
    end

    def totals_for(window)
      return totals_of(0, 0, 0) if window.nil?

      totals_of(*SearchConsole::Sums.pick(sliced(AhoyDashboard::SearchConsoleTotal.in_range(window))))
    end

    def windows
      @windows ||= SearchConsole::ComparedWindow.within(
        requested: range, covered: SearchConsole::Sums.extent(sliced(AhoyDashboard::SearchConsoleTotal.all))
      )
    end

    def rows
      @rows ||= begin
        found = queries? ? keyword_rows : page_rows
        trends = queries? ? trends_for(found.map(&:first)) : {}

        found.map do |label, clicks, impressions, weight|
          totals = totals_of(clicks, impressions, weight)

          Row.new(label, totals.clicks, totals.impressions, totals.ctr, totals.position, trends[label] || [])
        end
      end
    end

    def keyword_rows
      grouped(sliced(AhoyDashboard::SearchConsoleKeyword.in_range(range)), :query)
    end

    def page_rows
      grouped(sliced(AhoyDashboard::SearchConsoleRow.in_range(range)), :page)
    end

    def grouped(relation, column)
      narrowed(relation, column)
        .group(column)
        .order(SearchConsole::Sums::RANKING, column)
        .limit(limit)
        .pluck(column, *SearchConsole::Sums::ALL)
    end

    def narrowed(relation, column)
      return relation if term.blank?

      relation.where("#{column} ilike ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end

    def trends_for(labels)
      return {} if labels.empty?

      sliced(AhoyDashboard::SearchConsoleKeyword.in_range(trend_range))
        .where(query: labels)
        .group(:query, :date)
        .order(:date)
        .pluck(:query, SearchConsole::Sums::CLICKS)
        .each_with_object(Hash.new { |found, key| found[key] = [] }) do |(label, clicks), found|
          found[label] << clicks.to_i
        end
    end

    def trend_range
      from = [ range.end.to_date - (TREND_DAYS - 1), range.begin.to_date ].max

      (from..range.end.to_date)
    end

    def last_date
      days.last&.date
    end

    def sliced(relation)
      slice.apply(relation)
    end

    def totals_of(clicks, impressions, weight)
      SearchConsole::Totals.from(clicks: clicks, impressions: impressions, weight: weight)
    end
  end
end
