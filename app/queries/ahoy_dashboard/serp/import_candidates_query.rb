module AhoyDashboard
  module Serp
    class ImportCandidatesQuery
      DEFAULT_DAYS = 90
      DEFAULT_LIMIT = 50
      CACHE_PREFIX = "ahoy_dashboard/serp/import_candidates/v1".freeze
      CACHE_TTL = 1.hour

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

        AhoyDashboard.cache.fetch(cache_key, expires_in: CACHE_TTL) { rows }.map do |query, clicks, impressions, position|
          Candidate.new(query: query, clicks: clicks, impressions: impressions, position: position)
        end
      end

      private

      attr_reader :days, :limit

      def rows
        keywords = SearchConsoleKeyword.table_name
        tracked = SerpKeyword.select(Arel.sql("lower(#{SerpKeyword.table_name}.query)"))

        SearchConsoleKeyword.where(SearchConsoleKeyword.arel_table[:date].gteq(from))
          .where("lower(#{keywords}.query) not in (#{tracked.to_sql})")
          .group(:query)
          .order(Arel.sql("#{SearchConsole::Sums::IMPRESSIONS} desc, query asc"))
          .limit(limit)
          .pluck(:query, SearchConsole::Sums::CLICKS, SearchConsole::Sums::IMPRESSIONS, SearchConsole::Sums::POSITION)
          .map do |query, clicks, impressions, position|
            [ query, clicks.to_i, impressions.to_i, position.to_f.round(1) ]
          end
      end

      def cache_key
        count, changed = SerpKeyword.pick(Arel.sql("count(*)"), Arel.sql("max(updated_at)"))
        stored = SearchConsole::Sums.extent(SearchConsoleKeyword.all)
        parts = [ CACHE_PREFIX, days, limit, from, SearchConsoleDay.maximum(:scanned_at).to_f, stored&.begin, stored&.end,
                  count, changed.to_f ]

        AnalyticsCache.key(key: parts, connection: SearchConsoleKeyword.connection)
      end

      def from
        AhoyDashboard.time_zone.today - days
      end
    end
  end
end
