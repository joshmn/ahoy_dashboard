module AhoyDashboard
  module Seo
    module Backlinks
      class SyncsController < BaseController
        def create
          blocker = AhoyDashboard::Backlinks.refusal
          return redirect_to(seo_backlink_path, alert: AhoyDashboard::Backlinks.refusal_message(blocker)) if blocker

          AhoyDashboard::Backlinks::SyncJob.perform_later

          redirect_to seo_backlink_path, notice: "Pulling the backlink profile. Give it a minute."
        end

        private

        def surface_key
          "backlinks"
        end
      end
    end
  end
end
