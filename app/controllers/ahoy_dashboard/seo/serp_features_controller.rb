module AhoyDashboard
  module Seo
    class SerpFeaturesController < BaseController
      def show
        present(SerpFeaturesPresenter, result: SerpFeaturesQuery.call(site: @site, range: query.range, tag: tag))
      end

      private

      def surface_key
        "serp_features"
      end
    end
  end
end
