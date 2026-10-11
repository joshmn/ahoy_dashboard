module AhoyDashboard
  module Seo
    class KeywordResearchesController < BaseController
      def show
        result = KeywordIdeasQuery.call(seed: params[:seed], location: params[:location], language: params[:language])

        present(KeywordResearchPresenter, result: result, only: params[:only])
      end

      private

      def surface_key
        "keyword_research"
      end
    end
  end
end
