module AhoyDashboard
  module Seo
    class VisibilitiesController < BaseController
      def show
        present(VisibilityPresenter, result: VisibilityQuery.call(
          site: @site, range: query.range, weighting: params[:weighting], tag: tag
        ))
      end

      private

      def surface_key
        "visibility"
      end
    end
  end
end
