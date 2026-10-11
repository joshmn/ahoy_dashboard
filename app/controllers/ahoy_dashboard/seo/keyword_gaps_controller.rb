module AhoyDashboard
  module Seo
    class KeywordGapsController < BaseController
      def show
        present(KeywordGapPresenter, result: KeywordGapQuery.call(site: @site, range: query.range, tag: tag))
      end

      private

      def surface_key
        "keyword_gap"
      end
    end
  end
end
