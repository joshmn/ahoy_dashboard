module AhoyDashboard
  module Seo
    class ConversionQuery
      DEFAULT_LIMIT = 40

      Row = Data.define(:path, :clicks, :impressions, :position, :query, :visits, :visitors, :converting) do
        def ctr
          impressions.zero? ? 0.0 : clicks.to_f / impressions
        end

        def conversion_rate
          visits.zero? ? 0.0 : converting.to_f / visits
        end

        def landed?
          visits.positive?
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

        def converting_visits
          rows.sum(&:converting)
        end

        def rate
          visits.zero? ? 0.0 : converting_visits.to_f / visits
        end

        def converting
          rows.select { |row| row.converting.positive? }
        end

        def leaking
          rows.select { |row| row.clicks >= 20 && row.converting.zero? }
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

        pages.map do |path, (clicks, impressions, position)|
          visits = landings.fetch(path, ConversionVisitsQuery::NONE)
          Row.new(path: path, clicks: clicks, impressions: impressions, position: position, query: terms[path],
                  visits: visits.visits, visitors: visits.visitors, converting: visits.converting)
        end
      end

      def page_path
        PagePath.sql("landed.page")
      end

      def landed(*columns)
        relation = slice.apply(AhoyDashboard::SearchConsoleRow.in_range(range)).group(:page, *columns)
          .select("page", *columns.map(&:to_s), "#{SearchConsole::Sums::CLICKS} AS clicks",
                  "#{SearchConsole::Sums::IMPRESSIONS} AS impressions", "#{SearchConsole::Sums::WEIGHT} AS weight")

        AhoyDashboard::SearchConsoleRow.from(relation, :landed)
      end

      def pages
        @pages ||= landed
          .where("#{page_path} IS NOT NULL")
          .group(page_path)
          .order(Arel.sql("sum(clicks) DESC, #{page_path} ASC"))
          .limit(limit)
          .pluck(page_path, SearchConsole::Sums::CLICKS, SearchConsole::Sums::IMPRESSIONS,
                 Arel.sql("sum(weight) / nullif(sum(impressions), 0)"))
          .map { |path, clicks, impressions, position| [ path, [ clicks.to_i, impressions.to_i, position.to_f.round(1) ] ] }
          .to_h
      end

      def queries
        SearchConsole::Sums.best(landed(:query).where(Arel.sql(page_path).in(pages.keys)), key: page_path, pick: "query")
      end

      def goal_matcher
        return @goal_matcher if defined?(@goal_matcher)

        @goal_matcher = AhoyDashboard::Sql::GoalCompiler.match_case
      end
    end
  end
end
