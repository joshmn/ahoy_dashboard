module AhoyDashboard
  class SearchConsoleQuery
    Row = Data.define(:label, :clicks, :impressions, :ctr, :position)

    Totals = SearchConsole::Totals

    Coverage = Data.define(:counted_clicks, :counted_impressions, :total_clicks, :total_impressions) do
      def missing_clicks
        [ total_clicks - counted_clicks, 0 ].max
      end

      def missing_impressions
        [ total_impressions - counted_impressions, 0 ].max
      end

      def click_share
        return 0.0 if total_clicks.to_i.zero?

        (counted_clicks.to_f / total_clicks).clamp(0.0, 1.0)
      end

      def complete?
        missing_clicks.zero? && missing_impressions.zero?
      end

      def measurable?
        total_clicks.positive? || total_impressions.positive?
      end
    end

    Result = Data.define(:range, :queries, :pages, :totals, :coverage, :connected, :problem, :through) do
      def initialize(problem: nil, through: nil, **rest)
        super
      end

      def connected?
        connected
      end

      def any?
        totals.any? || queries.any?
      end

      def short?
        through.present? && range.end.to_date > through
      end
    end

    DEFAULT_LIMIT = 9
    MAX_LIMIT = 1_000

    class << self
      def call(**options)
        new(**options).call
      end
    end

    def initialize(range:, limit: DEFAULT_LIMIT, account: nil)
      @range = range
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
      @account = account || GoogleAccount.current
    end

    def call
      Result.new(range: range, queries: rows(:query), pages: rows(:page), totals: totals,
                 coverage: coverage, connected: account.present? && account.ready?,
                 problem: problem, through: stored_query.last_date)
    end

    private

    attr_reader :range, :limit, :account

    def stored_query
      @stored_query ||= SearchConsoleStoredQuery.new(range: range, limit: limit, account: account)
    end

    def stored
      @stored ||= stored_query.call
    end

    def problem
      account.last_error.presence if SearchConsole.enabled? && account.present? && account.ready?
    end

    def rows(column)
      stored.fetch(:top).fetch(column).map do |label, (clicks, impressions, weight)|
        reading = totals_of(clicks, impressions, weight)

        Row.new(label: label, clicks: reading.clicks, impressions: reading.impressions, ctr: reading.ctr,
                position: reading.position)
      end
    end

    def totals
      @totals ||= totals_of(*stored.fetch(:totals))
    end

    def coverage
      clicks, impressions = stored.fetch(:counted)
      Coverage.new(counted_clicks: clicks, counted_impressions: impressions,
                   total_clicks: totals.clicks, total_impressions: totals.impressions)
    end

    def totals_of(clicks, impressions, weight)
      Totals.from(clicks: clicks, impressions: impressions, weight: weight, places: 1)
    end
  end
end
