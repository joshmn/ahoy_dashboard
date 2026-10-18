module AhoyDashboard
  module SearchConsole
    class AnalyticsService < BaseService
      Row = Data.define(:keys, :clicks, :impressions, :ctr, :position)

      def initialize(date:, account: nil, dimensions: [], data_state: SearchConsole::DATA_STATE_FINAL,
                     row_limit: SearchConsole::MAX_ROWS)
        @account = account || GoogleAccount.current
        @date = date
        @dimensions = Array(dimensions).map(&:to_s)
        @data_state = data_state
        @row_limit = row_limit.to_i.clamp(1, SearchConsole::MAX_ROWS)
      end

      def call
        raise AuthError, "google is not connected" unless account&.connected?
        raise Error, "no search console property is selected" unless account.property_selected?

        token = AccessTokenService.call(account: account)
        rows = []
        start_row = 0

        loop do
          page = request(token, start_row)
          rows.concat(page)
          break if page.size < row_limit

          start_row += row_limit
        end

        rows
      end

      private

      attr_reader :account, :date, :dimensions, :data_state, :row_limit

      def request(token, start_row)
        payload = post_json(url, token, body(start_row))

        payload.fetch("rows", []).map { |row| build(row) }
      end

      def body(start_row)
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
