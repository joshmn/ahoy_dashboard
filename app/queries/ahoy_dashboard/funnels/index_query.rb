# frozen_string_literal: true

module AhoyDashboard

  module Funnels

    class IndexQuery
      PAGE_SIZE = 4

      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(query:, page: nil)
        @query = query
        @requested_page = page.to_s.to_i
      end

      def call
        total = Funnel.count
        pages = [(total.to_f / PAGE_SIZE).ceil, 1].max
        page = requested_page.clamp(1, pages)
        funnels = Funnel.ordered.limit(PAGE_SIZE).offset((page - 1) * PAGE_SIZE).includes(funnel_steps: :goal)
        readings = funnels.map { |funnel| FunnelQuery.call(scope: query.scope, funnel: funnel) }

        Page.new(readings: readings, total: total, page: page, pages: pages)
      end

      private

      attr_reader :query, :requested_page
    end
  end
end
