# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class OpportunityQuery
      DEFAULT_LIMIT = 60
      MINIMUM_IMPRESSIONS = 30
      Row = OpportunityRow
      Result = OpportunityResult

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
        relation = scope
        relation = relation.where("position > 10 AND position <= 20") if kind == :striking
        relation = relation.where("expected > 0 AND clicks < expected * 0.6") if kind == :under_performing
        order = kind == :under_performing ? "clicks - expected, upside DESC, impressions DESC, query" : "upside DESC, impressions DESC, query"
        found = relation.order(Arel.sql(order)).limit(limit).pluck(:query, :clicks, :impressions, :position)
        landing = pages(found.map(&:first))
        found.map do |query, clicks, impressions, position|
          Row.new(query: query, clicks: clicks, impressions: impressions, position: position, page: landing[query])
        end
      end

      def summary
        columns = ["COALESCE(SUM(clicks), 0)", "COALESCE(SUM(impressions), 0)", "COALESCE(SUM(upside), 0)",
                   "COUNT(*) FILTER (WHERE position > 10 AND position <= 20)",
                   "COUNT(*) FILTER (WHERE expected > 0 AND clicks < expected * 0.6)"]
        scope.pick(*columns.map { |column| Arel.sql(column) })
      end

      def days
        slice.apply(SearchConsoleKeyword.in_range(range)).distinct.count(:date)
      end

      private

      attr_reader :range, :limit, :slice

      def scope
        OpportunityScopeQuery.new(range: range, slice: slice).call
      end

      def pages(queries)
        return {} if queries.empty?

        slice.apply(SearchConsoleRow.in_range(range)).where(query: queries)
          .group(:query, :page).order(Arel.sql("query, SUM(clicks) DESC, SUM(impressions) DESC, page"))
          .pluck(Arel.sql("DISTINCT ON (query) query"), :page).to_h
      end
    end
  end
end
