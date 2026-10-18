# frozen_string_literal: true

module AhoyDashboard

  module Funnels

    class IndexPresenter
      def initialize(query:, result:, routes:)
        @query = query
        @result = result
        @routes = routes
      end

      def funnel_presenters
        @funnel_presenters ||= FunnelPresenter.wrap(result.readings, query: query)
      end

      def funnels
        funnel_presenters.map(&:funnel)
      end

      def empty?
        result.total.zero?
      end

      def summary
        return "No funnels configured" if empty?

        first = (result.page - 1) * IndexQuery::PAGE_SIZE + 1
        "Showing #{first}–#{first + funnel_presenters.length - 1} of #{result.total} funnels"
      end

      def range_label
        query.range_label
      end

      def paged?
        result.pages > 1
      end

      def page_label
        "Page #{result.page} of #{result.pages}"
      end

      def previous_page_path
        page_path(result.page - 1) if result.page > 1
      end

      def next_page_path
        page_path(result.page + 1) if result.page < result.pages
      end

      private

      attr_reader :query, :result, :routes

      def page_path(page)
        routes.funnels_path(query.to_query.merge(page: page))
      end
    end
  end
end
