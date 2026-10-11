module AhoyDashboard
  module Seo
    # Searches where two of our own pages are turning up for the same thing.
    #
    # It is not always a problem and the page does not pretend it is. Two pages
    # on one search is fine when one of them is clearly the answer and the other
    # is picking up scraps. It is a problem when the clicks are split, or when
    # the page Google keeps choosing is not the page that was written for the
    # search, and both of those are visible here and nowhere else.
    #
    # Query by page is the one grain that can answer this, and it is the grain
    # Search Console withholds the most at, so treat a quiet result as quiet
    # rather than as clean.
    class CannibalizationQuery
      DEFAULT_LIMIT = 40
      MINIMUM_IMPRESSIONS = 30

      # A second page holding at least this share of the search's clicks is a
      # split rather than a stray impression.
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

        # The two best pages within a place of each other means Google is
        # genuinely undecided rather than ranking one page and glancing at
        # another.
        def swapping?
          return false if runner_up.nil?

          (winner.position - runner_up.position).abs <= 3
        end

        def best_position
          pages.map(&:position).min
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
        PagePath.sql("#{AhoyDashboard::SearchConsoleRow.table_name}.page")
      end

      def rows
        return [] if contested.empty?

        pages_for(contested.keys).map do |query, pages|
          next if pages.size < 2

          totals = contested[query]

          Row.new(query: query, pages: pages.sort_by { |page| -page.clicks },
                  clicks: totals[:clicks], impressions: totals[:impressions])
        end.select { |value| value }.sort_by { |row| [ -row.clicks, -row.impressions ] }.first(limit)
      end

      # Which searches have more than one of our pages against them at all, and
      # what the search is worth in total. Two passes rather than one, because
      # the second pass only has to look at the searches this one found.
      def contested
        @contested ||= slice.apply(AhoyDashboard::SearchConsoleRow.in_range(range))
          .group(:query)
          .having(Arel.sql("count(distinct #{path}) > 1"))
          .having("sum(impressions) >= ?", MINIMUM_IMPRESSIONS)
          .select("query", "sum(clicks) as clicks", "sum(impressions) as impressions")
          .order(Arel.sql("sum(clicks) desc, sum(impressions) desc"))
          .limit(limit * 2)
          .map { |row| [ row.query, { clicks: row.clicks.to_i, impressions: row.impressions.to_i } ] }.to_h
      end

      def pages_for(queries)
        slice.apply(AhoyDashboard::SearchConsoleRow.in_range(range))
          .where(query: queries)
          .group(Arel.sql("query"), path)
          .select(
            "query", "#{path} as page",
            "sum(clicks) as clicks",
            "sum(impressions) as impressions",
            "count(distinct date) as days",
            "sum(position * impressions) / nullif(sum(impressions), 0) as position"
          )
          .to_a
          .group_by(&:query)
          .transform_values do |rows|
            rows.map do |row|
              Page.new(page: row.page, clicks: row.clicks.to_i, impressions: row.impressions.to_i,
                       position: row.position.to_f.round(1), days: row.days.to_i)
            end
          end
      end
    end
  end
end
