module AhoyDashboard
  module Seo
    class BacklinksController < BaseController
      def show
        present(BacklinkPresenter, result: BacklinksQuery.call(range: query.range))
      end

      private

      def surface_key
        "backlinks"
      end
    end
  end
end
