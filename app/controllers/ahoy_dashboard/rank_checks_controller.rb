module AhoyDashboard
  class RankChecksController < AhoyDashboard::BaseController
    requires_installed :serp

    def create
      AhoyDashboard::Serp::SweepCommand.call do
        on(:ok) { |searches| back(notice: "Checking #{helpers.pluralize(searches, 'search')}. Give it a minute, then reload.") }
        on(:refused) { |reason| back(alert: reason) }
      end
    end

    private

    def back(**flash_message)
      redirect_back fallback_location: rankings_path, **flash_message
    end
  end
end
