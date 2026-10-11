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

      def all
        @all ||= query.rows
      end

      def days
        @days ||= query.days
      end

      def any?
        rows.any?
      end

      def top(count = 25)
        rows.first(count)
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
        summary[0].to_i
      end

      def impressions
        summary[1].to_i
      end

      def upside
        summary[2].to_i
      end

      def striking_count
        summary[3].to_i
      end

      def under_performing_count
        summary[4].to_i
      end

      private

      attr_reader :query

      def summary
        @summary ||= query.summary
      end
    end
  end
end
