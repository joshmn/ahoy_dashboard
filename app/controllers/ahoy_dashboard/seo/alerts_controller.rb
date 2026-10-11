module AhoyDashboard
  module Seo
    class AlertsController < BaseController
      def show
        present(AlertPresenter, result: AlertsQuery.call(range: query.range, page: params[:page]))
      end

      private

      def surface_key
        "alerts"
      end
    end
  end
end
