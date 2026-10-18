# frozen_string_literal: true

module AhoyDashboard

  class SearchConsoleStoredQuery
    CACHE_PREFIX = "ahoy_dashboard/search_console/stored/v3".freeze
    CACHE_TTL = 1.hour

    def initialize(range:, limit:, account:)
      @range = range
      @limit = limit
      @account = account
    end

    def call
      AhoyDashboard.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        { top: { query: rows(SearchConsoleKeyword, :query), page: rows(SearchConsoleRow, :page) },
          totals: SearchConsole::Sums.pick(SearchConsoleTotal.in_range(range)),
          counted: SearchConsole::Sums.pick(SearchConsoleRow.in_range(range)) }
      end
    end

    def last_date
      return @last_date if defined?(@last_date)

      @last_date = SearchConsoleTotal.maximum(:date)
    end

    private

    attr_reader :range, :limit, :account

    def rows(model, column)
      model.in_range(range).group(column).order(SearchConsole::Sums::RANKING, column).limit(limit)
        .pluck(column, *SearchConsole::Sums::ALL)
        .map { |label, clicks, impressions, weight| [label, [clicks.to_i, impressions.to_i, weight.to_f]] }
    end

    def cache_key
      revision = SearchConsoleDay.maximum(:scanned_at)
      parts = [CACHE_PREFIX, (account.property_uri if account), range.begin.to_date, range.end.to_date, limit,
               (account.synced_at.to_f if account && account.synced_at), revision.to_f, last_date]
      AnalyticsCache.key(key: parts, connection: SearchConsoleRow.connection)
    end
  end
end
