module AhoyDashboard
  module Seo
    class CannibalizationQuery
      DEFAULT_LIMIT = 40
      MINIMUM_IMPRESSIONS = 30

      SPLIT_SHARE = 0.2

      Page = Data.define(:page, :clicks, :impressions, :position, :days) do
        def path
          return page if page.blank?

          page.sub(%r{\Ahttps?://[^/]+}, "").presence || "/"
        end
      end

      Row = Data.define(:query, :pages, :clicks, :impressions) do
        def contenders
          pages.size
        end

        def winner
          pages.max_by { |page| [ page.clicks, page.impressions ] }
        end

        def runner_up
          (pages - [ winner ]).max_by { |page| [ page.clicks, page.impressions ] }
        end

        def split
          return 0.0 if clicks.zero?

          runner_up.clicks.to_f / clicks
        end

        def split?
          split >= SPLIT_SHARE
        end

        def swapping?
          return false if runner_up.nil?

          (winner.position - runner_up.position).abs <= 3
        end

        def elsewhere
          pages.sum(&:clicks) - winner.clicks
        end

        def severity
          return :high if split? && swapping?
          return :medium if split? || swapping?

          :low
        end
      end

      Result = Data.define(:range, :rows, :limit) do
        def any?
          rows.any?
        end

        def of(severity)
          rows.select { |row| row.severity == severity }
        end

        def high
          of(:high)
        end

        def clicks_at_risk
          rows.sum(&:elsewhere)
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:, limit: DEFAULT_LIMIT, slice: AhoyDashboard::SearchConsole::Slice.new)
        @range = range
        @limit = limit
        @slice = slice
      end

      def call
        Result.new(range: range, rows: rows, limit: limit)
      end

      private

      attr_reader :range, :limit, :slice

      def path
        PagePath.sql("landed.page")
      end

      def rows
        return [] if contested.empty?

        pages_for(contested.keys).map do |query, pages|
          next if pages.size < 2

          clicks, impressions = contested[query]

          Row.new(query: query, pages: pages.sort_by { |page| -page.clicks }, clicks: clicks, impressions: impressions)
        end.select { |value| value }.sort_by { |row| [ -row.clicks, -row.impressions ] }.first(limit)
      end

      def search_rows
        slice.apply(AhoyDashboard::SearchConsoleRow.in_range(range))
      end

      def contested
        @contested ||= begin
          landed = search_rows.group(:query, :page)
            .select("query", "page", "#{SearchConsole::Sums::CLICKS} AS clicks",
                    "#{SearchConsole::Sums::IMPRESSIONS} AS impressions")

          AhoyDashboard::SearchConsoleRow.from(landed, :landed)
            .group(Arel.sql("query"))
            .having(Arel.sql("count(distinct #{path}) > 1"))
            .having("#{SearchConsole::Sums::IMPRESSIONS} >= ?", MINIMUM_IMPRESSIONS)
            .order(SearchConsole::Sums::RANKING)
            .limit(limit * 2)
            .pluck(Arel.sql("query"), SearchConsole::Sums::CLICKS, SearchConsole::Sums::IMPRESSIONS)
            .map { |query, clicks, impressions| [ query, [ clicks.to_i, impressions.to_i ] ] }.to_h
        end
      end

      def pages_for(queries)
        landed = search_rows.where(query: queries).group(:query, :page, :date)
          .select("query", "page", "date", "#{SearchConsole::Sums::CLICKS} AS clicks",
                  "#{SearchConsole::Sums::IMPRESSIONS} AS impressions", "#{SearchConsole::Sums::WEIGHT} AS weight")

        AhoyDashboard::SearchConsoleRow.from(landed, :landed)
          .group(Arel.sql("query"), path)
          .pluck(Arel.sql("query"), path, SearchConsole::Sums::CLICKS, SearchConsole::Sums::IMPRESSIONS,
                 Arel.sql("count(distinct date)"), Arel.sql("sum(weight) / nullif(sum(impressions), 0)"))
          .group_by(&:first)
          .transform_values do |rows|
            rows.map do |_query, page, clicks, impressions, days, position|
              Page.new(page: page, clicks: clicks.to_i, impressions: impressions.to_i,
                       position: position.to_f.round(1), days: days.to_i)
            end
          end
      end
    end
  end
end
