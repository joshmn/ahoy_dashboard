module AhoyDashboard
  module Seo
    module Alerts
      class RunsController < BaseController
        def create
          AhoyDashboard::Alerts::RunJob.perform_later

          redirect_to seo_alert_path, notice: "Checking every rule that is switched on."
        end

        private

        def surface_key
          "alerts"
        end
      end
    end
  end
end
