# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class OpportunityResult
      attr_reader :range, :limit

      def initialize(range:, limit:, query:)
        @range = range
        @limit = limit
        @query = query
      end

      def rows
        @rows ||= query.rows(limit: limit)
      end

      def any?
        rows.any?
      end

      def striking(limit: nil)
        @striking ||= {}
        @striking[limit] ||= query.rows(limit: limit, kind: :striking)
      end

      def under_performing(limit: nil)
        @under_performing ||= {}
        @under_performing[limit] ||= query.rows(limit: limit, kind: :under_performing)
      end

      def clicks
        candidates.sum(&:clicks)
      end

      def impressions
        candidates.sum(&:impressions)
      end

      def upside
        candidates.sum(&:upside)
      end

      def striking_count
        candidates.count(&:striking?)
      end

      def under_performing_count
        candidates.count(&:under_performing?)
      end

      private

      attr_reader :query

      def candidates
        query.candidates
      end
    end
  end
end
