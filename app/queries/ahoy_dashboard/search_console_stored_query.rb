# frozen_string_literal: true

module AhoyDashboard

  class SearchConsoleStoredQuery
    CACHE_PREFIX = "ahoy_dashboard/search_console/stored/v2".freeze
    CACHE_TTL = 1.hour
    SUM_CLICKS = Arel.sql("sum(clicks)").freeze
    SUM_IMPRESSIONS = Arel.sql("sum(impressions)").freeze
    SUM_POSITION = Arel.sql("sum(position * impressions)").freeze
    RANKING = [Arel.sql("sum(clicks) desc"), Arel.sql("sum(impressions) desc")].freeze

    def initialize(range:, limit:, account:)
      @range = range
      @limit = limit
      @account = account
    end

    def call
      AhoyDashboard.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        {top: {query: rows(:query), page: rows(:page)},
         totals: sums(SearchConsoleTotal.in_range(range)),
         counted: sums(SearchConsoleRow.in_range(range))}
      end
    end

    def last_date
      return @last_date if defined?(@last_date)

      @last_date = SearchConsoleTotal.maximum(:date)
    end

    private

    attr_reader :range, :limit, :account

    def rows(column)
      SearchConsoleRow.in_range(range).group(column).order(*RANKING, column).limit(limit)
        .pluck(column, SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION)
        .map { |label, clicks, impressions, weight| [label, [clicks.to_i, impressions.to_i, weight.to_f]] }
    end

    def sums(relation)
      clicks, impressions, weight = relation.pick(SUM_CLICKS, SUM_IMPRESSIONS, SUM_POSITION)
      [clicks.to_i, impressions.to_i, weight.to_f]
    end

    def cache_key
      revision = SearchConsoleDay.maximum(:scanned_at)
      parts = [CACHE_PREFIX, (account.property_uri if account), range.begin.to_date, range.end.to_date, limit,
               (account.synced_at.to_f if account && account.synced_at), revision.to_f, last_date]
      AnalyticsCache.key(key: parts, connection: SearchConsoleRow.connection)
    end
  end
end
