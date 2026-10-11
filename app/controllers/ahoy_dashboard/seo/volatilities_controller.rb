module AhoyDashboard
  module Seo
    class VolatilitiesController < BaseController
      def show
        present(VolatilityPresenter, result: VolatilityQuery.call(range: query.range, tag: tag))
      end

      private

      def surface_key
        "volatility"
      end
    end
  end
end
