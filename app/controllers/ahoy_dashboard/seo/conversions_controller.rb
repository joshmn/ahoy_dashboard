module AhoyDashboard
  module Seo
    class ConversionsController < BaseController
      def show
        present(ConversionPresenter, result: ConversionQuery.call(range: query.range, slice: slice),
          totals: (PropertyTotalsQuery.call(range: query.range, slice: slice) if request_format == :html))
      end

      private

      def surface_key
        "conversions"
      end
    end
  end
end
