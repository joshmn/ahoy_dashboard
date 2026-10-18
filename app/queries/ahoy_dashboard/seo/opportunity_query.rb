# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class OpportunityQuery
      DEFAULT_LIMIT = 60
      MINIMUM_IMPRESSIONS = 30
      Result = OpportunityResult

      Row = Data.define(:query, :clicks, :impressions, :position, :upside, :expected, :page) do
        def ctr
          impressions.zero? ? 0.0 : clicks.to_f / impressions
        end

        def under_performing?
          expected.positive? && clicks < expected * 0.6
        end

        def striking?
          position > 10 && position <= 20
        end

        def band
          return "Holding" if position <= 3
          return "Page one" if position <= 10
          return "Striking distance" if striking?

          "Deep"
        end
      end

      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(range:, limit: DEFAULT_LIMIT, slice: SearchConsole::Slice.new)
        @range = range
        @limit = limit.to_i.clamp(1, 200)
        @slice = slice
      end

      def call
        Result.new(range: range, limit: limit, query: self)
      end

      def rows(limit: nil, kind: nil)
        found = of_kind(kind)
        found = found.first(limit) if limit
        landing = pages(found.map(&:query))

        found.map { |row| row.with(page: landing[row.query]) }
      end

      def candidates
        @candidates ||= SearchConsoleKeyword.from("(#{aggregated.to_sql}) opportunity_totals")
          .order(Arel.sql("upside DESC, impressions DESC, query"))
          .pluck(Arel.sql("query, clicks, impressions, position, #{upside} AS upside, #{expected} AS expected"))
          .map do |query, clicks, impressions, position, upside, expected|
            Row.new(query: query, clicks: clicks.to_i, impressions: impressions.to_i, position: position.to_f,
                    upside: upside.to_i, expected: expected.to_i, page: nil)
          end
      end

      private

      attr_reader :range, :limit, :slice

      def of_kind(kind)
        return candidates.select(&:striking?) if kind == :striking
        return under_performing if kind == :under_performing

        candidates
      end

      def under_performing
        candidates.select(&:under_performing?).each_with_index
          .sort_by { |row, order| [ row.clicks - row.expected, order ] }
          .map(&:first)
      end

      def aggregated
        slice.apply(SearchConsoleKeyword.in_range(range)).group(:query)
          .having("#{SearchConsole::Sums::IMPRESSIONS} >= ?", MINIMUM_IMPRESSIONS)
          .select("query", "#{SearchConsole::Sums::CLICKS} AS clicks",
                  "#{SearchConsole::Sums::IMPRESSIONS} AS impressions",
                  "ROUND((#{SearchConsole::Sums::POSITION})::numeric, 1)::float AS position")
      end

      def upside
        "CASE WHEN position <= #{CtrCurve::REALISTIC_TARGET} THEN 0 " \
          "ELSE GREATEST(ROUND((impressions * #{CtrCurve.target} - clicks)::numeric), 0) END"
      end

      def expected
        curve = CtrCurve::BY_POSITION.map { |position, rate| "WHEN #{position} THEN #{rate}" }.join(" ")
        "ROUND(impressions * (CASE FLOOR(position) #{curve} ELSE 0 END))"
      end

      def pages(queries)
        return {} if queries.empty?

        SearchConsole::Sums.best(slice.apply(SearchConsoleRow.in_range(range)).where(query: queries),
                                 key: "query", pick: "page")
      end
    end
  end
end
