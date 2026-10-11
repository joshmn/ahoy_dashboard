# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class OpportunityRow
      attr_reader :query, :clicks, :impressions, :position, :page, :ctr

      def initialize(query:, clicks:, impressions:, position:, page:)
        @query = query
        @clicks = clicks.to_i
        @impressions = impressions.to_i
        @position = position.to_f.round(1)
        @page = page
        @ctr = impressions.to_i.zero? ? 0.0 : clicks.to_f / impressions.to_i
      end

      def target
        CtrCurve::REALISTIC_TARGET
      end

      def target_ctr
        CtrCurve.target
      end

      def expected
        (impressions * CtrCurve.at_average(position)).round
      end

      def under_performing?
        expected.positive? && clicks < expected * 0.6
      end

      def upside
        return 0 if position <= target

        [(impressions * target_ctr - clicks).round, 0].max
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
  end
end
