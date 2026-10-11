module AhoyDashboard
  module Seo
    class LandingPagesController < BaseController
      def show
        present(LandingPagesPresenter, result: LandingPagesQuery.call(site: @site, range: query.range, tag: tag))
      end

      private

      def surface_key
        "landing_pages"
      end
    end
  end
end
