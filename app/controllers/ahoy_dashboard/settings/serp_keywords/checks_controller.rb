module AhoyDashboard
  module Settings
    module SerpKeywords
      class ChecksController < AhoyDashboard::Settings::BaseController
        requires_installed :serp

        def create
          keyword = AhoyDashboard::SerpKeyword.find(params[:serp_keyword_id])

          AhoyDashboard::Serp::SweepCommand.call(keyword: keyword) do
            on(:ok) do |searches|
              back(notice: "Checking #{keyword.query} from #{helpers.pluralize(searches, 'place')}. " \
                           "Give it a minute, then reload.")
            end
            on(:refused) { |reason| back(alert: reason) }
          end
        end

        private

        def back(**flash_message)
          redirect_back fallback_location: settings_serp_keywords_path, **flash_message
        end
      end
    end
  end
end
