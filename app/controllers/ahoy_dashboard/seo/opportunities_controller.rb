module AhoyDashboard
  module Seo
    class OpportunitiesController < BaseController
      def show
        present(OpportunityPresenter, result: OpportunityQuery.call(range: query.range, slice: slice),
          totals: (PropertyTotalsQuery.call(range: query.range, slice: slice) if request_format == :html))
      end

      private

      def surface_key
        "opportunities"
      end
    end
  end
end
