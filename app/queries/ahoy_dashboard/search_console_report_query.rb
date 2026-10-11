module AhoyDashboard
  # Everything the Search Console page reads, as it is stored.
  #
  # Three tables at three grains, and the page is honest about which one each
  # number came from. The day totals are the only thing that is the whole day;
  # the keyword table is one row per query per day; the row table is the query by
  # page grain underneath both. None of the three add up to each other and all
  # three are right about their own question, which is why the page names its
  # source beside every block rather than presenting one number.
  class SearchConsoleReportQuery
    DEFAULT_ROWS = 25
    MAX_ROWS = 200
    TREND_DAYS = 28

    SUM_CLICKS = Arel.sql("sum(clicks)").freeze
    SUM_IMPRESSIONS = Arel.sql("sum(impressions)").freeze
    # Position is an average over impressions, so it is summed weighted and
    # divided back out. Averaging the averages would weigh a day with three
    # impressions the same as a day with three thousand.
    SUM_POSITION = Arel.sql("sum(position * impressions)").freeze

    Totals = Data.define(:clicks, :impressions, :ctr, :position) do
      def any?
        clicks.positive? || impressions.positive?
      end
    end

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
        totals: build_totals(*daily_sums),
        previous: totals_for(previous_range),
        previous_window: previous_range,
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

    # The chart. One point per day out of the totals table, which is the only
    # table that is the whole day.
    def days
      @days ||= daily_rows.map do |on, clicks, impressions, weight|
          totals = build_totals(clicks, impressions, weight)

          Day.new(on, totals.clicks, totals.impressions, totals.ctr, totals.position)
        end
    end

    def daily_rows
      @daily_rows ||= sliced(AhoyDashboard::SearchConsoleTotal.in_range(range))
        .group(:date).order(:date).pluck(:date, SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION)
    end

    def daily_sums
      [daily_rows.sum { |row| row[1].to_i }, daily_rows.sum { |row| row[2].to_i },
       daily_rows.sum { |row| row[3].to_f }]
    end

    def totals_for(window)
      return Totals.new(0, 0, 0.0, 0.0) if window.nil?

      clicks, impressions, weight = sliced(AhoyDashboard::SearchConsoleTotal.in_range(window))
        .pick(SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION)

      build_totals(clicks, impressions, weight)
    end

    def previous_range
      return @previous_range if defined?(@previous_range)

      @previous_range = begin
        window = compared_window

        if window
          length = (window.end - window.begin).to_i + 1
          candidate = (window.begin - length)..(window.begin - 1)

          candidate if candidate.begin >= covered.begin
        end
      end
    end

    def compared_window
      return nil if covered.nil?

      first = [ range.begin.to_date, covered.begin ].max
      last = [ range.end.to_date, covered.end ].min

      first <= last ? first..last : nil
    end

    def covered
      return @covered if defined?(@covered)

      first, last = sliced(AhoyDashboard::SearchConsoleTotal.all).pick(Arel.sql("min(date)"), Arel.sql("max(date)"))

      @covered = first && (first..last)
    end

    def rows
      @rows ||= begin
        found = queries? ? keyword_rows : page_rows
        trends = queries? ? trends_for(found.map(&:first)) : {}

        found.map do |label, clicks, impressions, weight|
          totals = build_totals(clicks, impressions, weight)

          Row.new(label, totals.clicks, totals.impressions, totals.ctr, totals.position, trends[label] || [])
        end
      end
    end

    # Queries come off the keyword table, not the row table. Google withholds far
    # more at query by page than at query alone, so a query summed out of the row
    # table is short of what it really did.
    def keyword_rows
      grouped(sliced(AhoyDashboard::SearchConsoleKeyword.in_range(range)), :query)
    end

    # Pages have no table of their own, so they are summed out of the row table
    # and are short in the same way. The page total is still the right shape for
    # ranking, which is what this list is for.
    def page_rows
      grouped(sliced(AhoyDashboard::SearchConsoleRow.in_range(range)), :page)
    end

    def grouped(relation, column)
      narrowed(relation, column)
        .group(column)
        .order(Arel.sql("sum(clicks) desc"), Arel.sql("sum(impressions) desc"), column)
        .limit(limit)
        .pluck(column, SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION)
    end

    # The filter box. A LIKE rather than a select over what came back, because
    # the list is the top however-many out of everything the range holds and
    # filtering the page would answer with whatever happened to be listed.
    def narrowed(relation, column)
      return relation if term.blank?

      relation.where("#{column} ilike ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end

    # One sparkline per query, drawn from the same table the query row came from.
    # A single grouped read for the whole page rather than one per row.
    def trends_for(labels)
      return {} if labels.empty?

      sliced(AhoyDashboard::SearchConsoleKeyword.in_range(trend_range))
        .where(query: labels)
        .group(:query, :date)
        .order(:date)
        .pluck(:query, SUM_CLICKS)
        .each_with_object(Hash.new { |found, key| found[key] = [] }) do |(label, clicks), found|
          found[label] << clicks.to_i
        end
    end

    # The sparkline is a shape rather than a reading, so it is capped at a length
    # that draws legibly in 90px however wide the range is.
    def trend_range
      from = [ range.end.to_date - (TREND_DAYS - 1), range.begin.to_date ].max

      (from..range.end.to_date)
    end

    # Google lands two to three days late, so the last day stored is the honest
    # end of the chart rather than today.
    def last_date
      days.last&.date
    end

    def sliced(relation)
      slice.apply(relation)
    end

    def build_totals(clicks, impressions, weight)
      clicks = clicks.to_i
      impressions = impressions.to_i

      Totals.new(
        clicks,
        impressions,
        impressions.positive? ? clicks.to_f / impressions : 0.0,
        impressions.positive? ? weight.to_f / impressions : 0.0
      )
    end
  end
end
