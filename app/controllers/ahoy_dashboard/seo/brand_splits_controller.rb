module AhoyDashboard
  module Seo
    class BrandSplitsController < BaseController
      def show
        totals = PropertyTotalsQuery.call(range: query.range, slice: slice)
        present(BrandSplitPresenter, totals: totals,
          result: BrandSplitQuery.call(range: query.range, slice: slice, property_totals: totals))
      end

      private

      def surface_key
        "brand_split"
      end
    end
  end
end
