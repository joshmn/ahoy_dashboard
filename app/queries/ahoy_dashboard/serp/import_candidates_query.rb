module AhoyDashboard
  module Serp
    class ImportCandidatesQuery
      DEFAULT_DAYS = 90
      DEFAULT_LIMIT = 50

      Candidate = Data.define(:query, :clicks, :impressions, :position)

      def self.call(**options)
        new(**options).call
      end

      def initialize(days: DEFAULT_DAYS, limit: DEFAULT_LIMIT)
        @days = days
        @limit = limit
      end

      def call
        return [] unless SearchConsole.installed?

        rows.map do |row|
          Candidate.new(query: row.query, clicks: row.clicks.to_i, impressions: row.impressions.to_i,
                        position: row.position.to_f.round(1))
        end
      end

      private

      attr_reader :days, :limit

      def rows
        SearchConsoleKeyword.where(SearchConsoleKeyword.arel_table[:date].gteq(from)).where.not(query: SerpKeyword.select(:query)).group(:query)
          .select(
            "query",
            "sum(clicks) as clicks",
            "sum(impressions) as impressions",
            "sum(position * impressions) / nullif(sum(impressions), 0) as position"
          )
          .order(Arel.sql("sum(impressions) desc, query asc"))
          .limit(limit)
      end

      def from
        AhoyDashboard.time_zone.today - days
      end
    end
  end
end
