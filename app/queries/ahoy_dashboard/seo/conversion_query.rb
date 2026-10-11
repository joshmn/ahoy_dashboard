module AhoyDashboard
  module Seo
    # The keyword, the page it landed on, and what the visit went on to do.
    #
    # No SEO tool can answer this, and not because it is hard. They stop at the
    # landing page because they never see the other half: the visit, the second
    # page, the goal. Both halves are already in this one database, so the join
    # is a query rather than an integration.
    #
    # Two caveats the page repeats rather than hides. Google's click count and
    # ahoy's visit count will not agree, ever: one is measured at the results
    # page and one in the browser, and blocking, prefetching and bounces off the
    # back button move them apart. And Search Console withholds queries, so the
    # keyword beside a page is the best known rather than the only one.
    class ConversionQuery
      DEFAULT_LIMIT = 40

      Row = Data.define(:path, :clicks, :impressions, :position, :query, :visits, :visitors,
                        :conversions, :converting, :goals) do
        def ctr
          impressions.zero? ? 0.0 : clicks.to_f / impressions
        end

        def conversion_rate
          visits.zero? ? 0.0 : converting.to_f / visits
        end

        # Clicks Google counted that never became a visit here. Some of this is
        # always measurement rather than loss, so it is only worth reading when
        # it is large.
        def shortfall
          [ clicks - visits, 0 ].max
        end

        def landed?
          visits.positive?
        end

        def top_goal
          goals.max_by { |_name, count| count }&.first
        end
      end

      Result = Data.define(:range, :rows, :limit, :goals_defined) do
        def any?
          rows.any?
        end

        def clicks
          rows.sum(&:clicks)
        end

        def visits
          rows.sum(&:visits)
        end

        def conversions
          rows.sum(&:conversions)
        end

        def converting_visits
          rows.sum(&:converting)
        end

        def rate
          visits.zero? ? 0.0 : converting_visits.to_f / visits
        end

        def converting
          rows.select { |row| row.conversions.positive? }
        end

        # Pages taking search traffic and doing nothing with it. The list worth
        # opening the page for, and the one no keyword tool can produce.
        def leaking
          rows.select { |row| row.clicks >= 20 && row.conversions.zero? }
            .sort_by { |row| -row.clicks }
        end

        def goals?
          goals_defined
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
        Result.new(range: range, rows: rows, limit: limit,
                   goals_defined: AhoyDashboard::Goal.any?)
      end

      private

      attr_reader :range, :limit, :slice

      def rows
        return [] if pages.empty?

        landings = ConversionVisitsQuery.call(range: range, slice: slice, paths: pages.keys, matcher: goal_matcher)
        terms = queries

        pages.map do |path, totals|
          visits = landings.fetch(path) { ConversionVisitResult.new }
          Row.new(path: path, clicks: totals[:clicks], impressions: totals[:impressions],
                  position: totals[:position], query: terms[path],
                  visits: visits.visits, visitors: visits.visitors,
                  conversions: visits.converting, converting: visits.converting,
                  goals: visits.goals)
        end
      end

      # Search Console records the page as a full URL. Everything on the ahoy
      # side is a path. One of them has to give, and it is this one, because a
      # path is what a person reads and what the rest of the dashboard groups by.
      def page_path
        PagePath.sql("#{AhoyDashboard::SearchConsoleRow.table_name}.page")
      end

      def search_rows
        slice.apply(AhoyDashboard::SearchConsoleRow.in_range(range))
      end

      def pages
        @pages ||= search_rows
          .where("#{page_path} IS NOT NULL")
          .group(page_path)
          .order(Arel.sql("sum(clicks) DESC, #{page_path} ASC"))
          .limit(limit)
          .select(
            "#{page_path} as path",
            "sum(clicks) as clicks",
            "sum(impressions) as impressions",
            "sum(position * impressions) / nullif(sum(impressions), 0) as position"
          )
          .each_with_object({}) do |row, found|
            next if row.path.nil?

            found[row.path] = { clicks: row.clicks.to_i, impressions: row.impressions.to_i,
                                position: row.position.to_f.round(1) }
          end
      end

      # The best known search for each page. Best known rather than best: Google
      # withholds the rare and the personal, so this is the top of what was
      # served rather than the top of what happened.
      def queries
        search_rows
          .where(Arel.sql(page_path).in(pages.keys))
          .group(page_path, Arel.sql("query"))
          .order(Arel.sql("#{page_path}, sum(clicks) desc, sum(impressions) desc, query"))
          .pluck(Arel.sql("distinct on (#{page_path}) #{page_path}"), :query)
          .each_with_object({}) { |(path, query), found| found[path] = query if path }
      end

      def goal_matcher
        return @goal_matcher if defined?(@goal_matcher)

        @goal_matcher = AhoyDashboard::Sql::GoalCompiler.match_case
      end
    end
  end
end
