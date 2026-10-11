module AhoyDashboard
  module Seo
    class PositionChangesController < BaseController
      def show
        present(PositionChangesPresenter,
                result: PositionChangesQuery.call(site: @site, range: query.range, tag: tag))
      end

      private

      def surface_key
        "position_changes"
      end
    end
  end
end
