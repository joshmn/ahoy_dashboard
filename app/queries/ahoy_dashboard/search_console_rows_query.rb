module AhoyDashboard
  class SearchConsoleRowsQuery
    PER_PAGE = 100
    MAX_LIMIT = 500

    SORTS = {
      "clicks" => { clicks: :desc, impressions: :desc },
      "impressions" => { impressions: :desc, clicks: :desc },
      "date" => { date: :desc, clicks: :desc },
      "position" => { position: :asc, impressions: :desc }
    }.freeze

    DEFAULT_SORT = "clicks".freeze

    Day = Data.define(:date, :rows, :row_clicks, :row_impressions, :total_clicks, :total_impressions) do
      def coverage
        return nil unless total_clicks.to_i.positive?

        (row_clicks.to_f / total_clicks).clamp(0.0, 1.0)
      end

      def missing_clicks
        [ total_clicks.to_i - row_clicks.to_i, 0 ].max
      end
    end

    Result = Data.define(:rows, :days, :page, :pages, :total_rows, :sort, :term, :range) do
      def any?
        rows.any?
      end

      def more?
        page < pages
      end
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(page: 1, sort: DEFAULT_SORT, term: nil, per_page: PER_PAGE)
      @page = [ page.to_i, 1 ].max
      @sort = SORTS.key?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @term = term.to_s.strip
      @per_page = per_page.to_i.clamp(1, MAX_LIMIT)
    end

    def call
      total = rows_by_date.values.sum(&:last)

      Result.new(
        rows: page_of_rows,
        days: days,
        page: page,
        pages: [ (total / per_page.to_f).ceil, 1 ].max,
        total_rows: total,
        sort: sort,
        term: term,
        range: stored_range
      )
    end

    private

    attr_reader :page, :sort, :term, :per_page

    def matching
      relation = AhoyDashboard::SearchConsoleRow.all
      return relation if term.blank?

      relation.where(matching_predicate)
    end

    def matching_predicate
      like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"

      AhoyDashboard::SearchConsoleRow.sanitize_sql_array([ "query ilike :like or page ilike :like", { like: like } ])
    end

    def page_of_rows
      matching.order(**SORTS.fetch(sort)).limit(per_page).offset((page - 1) * per_page)
    end

    def days
      totals = AhoyDashboard::SearchConsoleTotal.group(:date)
        .pluck(:date, SearchConsole::Sums::CLICKS, SearchConsole::Sums::IMPRESSIONS)
        .map { |date, clicks, impressions| [ date, [ clicks, impressions ] ] }.to_h

      grouped = rows_by_date

      (totals.keys | grouped.keys).sort.reverse.map do |date|
        count, clicks, impressions = grouped.fetch(date, [ 0, 0, 0 ])
        total_clicks, total_impressions = totals.fetch(date, [ nil, nil ])

        Day.new(date: date, rows: count, row_clicks: clicks.to_i, row_impressions: impressions.to_i,
                total_clicks: total_clicks, total_impressions: total_impressions)
      end
    end

    def stored_range
      first, last = rows_by_date.keys.minmax
      return nil if first.nil?

      first..last
    end

    def rows_by_date
      @rows_by_date ||= begin
        matched = term.blank? ? "count(*)" : "count(*) filter (where #{matching_predicate})"

        AhoyDashboard::SearchConsoleRow.group(:date)
          .pluck(Arel.sql("date, count(*), #{SearchConsole::Sums::CLICKS}, #{SearchConsole::Sums::IMPRESSIONS}, #{matched}"))
          .map { |date, count, clicks, impressions, matching| [ date, [ count, clicks, impressions, matching ] ] }.to_h
      end
    end
  end
end
