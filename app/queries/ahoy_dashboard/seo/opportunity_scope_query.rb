# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class OpportunityScopeQuery
      def initialize(range:, slice:)
        @range = range
        @slice = slice
      end

      def call
        rated = base.from("(#{aggregated.to_sql}) opportunity_totals")
          .select("opportunity_totals.*", "#{upside} AS upside", "#{expected} AS expected")
        base.from("(#{rated.to_sql}) opportunities")
      end

      private

      attr_reader :range, :slice

      def base
        AhoyDashboard::SearchConsoleKeyword.unscoped
      end

      def aggregated
        slice.apply(base.in_range(range)).group(:query)
          .having("SUM(impressions) >= ?", OpportunityQuery::MINIMUM_IMPRESSIONS)
          .select("query", "SUM(clicks) AS clicks", "SUM(impressions) AS impressions",
                  "ROUND((SUM(position * impressions) / NULLIF(SUM(impressions), 0))::numeric, 1)::float AS position")
      end

      def upside
        "CASE WHEN position <= #{CtrCurve::REALISTIC_TARGET} THEN 0 " \
          "ELSE GREATEST(ROUND((impressions * #{CtrCurve.target} - clicks)::numeric), 0) END"
      end

      def expected
        curve = CtrCurve::BY_POSITION.map { |position, rate| "WHEN #{position} THEN #{rate}" }.join(" ")
        "ROUND(impressions * (CASE FLOOR(position) #{curve} ELSE 0 END))"
      end
    end
  end
end
