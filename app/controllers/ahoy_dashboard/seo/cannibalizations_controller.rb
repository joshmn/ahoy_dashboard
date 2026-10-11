module AhoyDashboard
  module Seo
    class CannibalizationsController < BaseController
      def show
        present(CannibalizationPresenter, result: CannibalizationQuery.call(range: query.range, slice: slice))
      end

      private

      def surface_key
        "cannibalization"
      end
    end
  end
end
