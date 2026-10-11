module AhoyDashboard
  module SearchConsole
    # searchAnalytics.query, one day at a time.
    #
    # Two things force the shape. Google serves at most 50,000 rows per day per
    # search type, sorted by clicks, and a wider date range does not raise that
    # ceiling, it just drops the tail without saying so. And a single response
    # carries rowLimit rows at most, so each day is paged through startRow until
    # a page comes back short.
    #
    # Ingestion reads query/page, query, and overall totals separately for each
    # day. Those grains need not agree: Google withholds rows differently at
    # each grain.
    class AnalyticsService < BaseService
      Row = Data.define(:keys, :clicks, :impressions, :ctr, :position)

      def initialize(dates:, account: nil, dimensions: [], data_state: SearchConsole::DATA_STATE_FINAL,
                     row_limit: SearchConsole::MAX_ROWS)
        @account = account || GoogleAccount.current
        @dates = Array(dates)
        @dimensions = Array(dimensions).map(&:to_s)
        @data_state = data_state
        @row_limit = row_limit.to_i.clamp(1, SearchConsole::MAX_ROWS)
      end

      # date => rows for that date.
      def call
        raise AuthError, "google is not connected" unless account&.connected?
        raise Error, "no search console property is selected" unless account.property_selected?

        token = AccessTokenService.call(account: account)

        dates.index_with { |date| fetch(token, date) }
      end

      private

      attr_reader :account, :dates, :dimensions, :data_state, :row_limit

      def fetch(token, date)
        rows = []
        start_row = 0

        loop do
          page = request(token, date, start_row)
          rows.concat(page)
          break if page.size < row_limit

          start_row += row_limit
        end

        rows
      end

      def request(token, date, start_row)
        payload = post_json(url, token, body(date, start_row))

        payload.fetch("rows", []).map { |row| build(row) }
      end

      def body(date, start_row)
        body = {
          startDate: date.to_s,
          endDate: date.to_s,
          type: SearchConsole::SEARCH_TYPE,
          rowLimit: row_limit,
          startRow: start_row,
          dataState: data_state
        }
        body[:dimensions] = dimensions if dimensions.any?
        body
      end

      # clicks and impressions arrive as JSON doubles even though they are whole
      # numbers, so they are read as floats and rounded by whoever stores them.
      def build(row)
        Row.new(
          keys: Array(row["keys"]),
          clicks: row["clicks"].to_f,
          impressions: row["impressions"].to_f,
          ctr: row["ctr"].to_f,
          position: row["position"].to_f
        )
      end

      def url
        @url ||= SearchConsole.analytics_url(account.property_uri)
      end
    end
  end
end
