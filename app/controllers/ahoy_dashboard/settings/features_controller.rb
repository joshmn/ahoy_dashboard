module AhoyDashboard
  module Settings
    class FeaturesController < AhoyDashboard::Settings::BaseController
      def index
        @features = AhoyDashboard::Features.all
      end

      def update
        feature = AhoyDashboard::Features.find(params[:name]) || raise(ActiveRecord::RecordNotFound)

        AhoyDashboard::Features::SwitchCommand.call(feature: feature, enabled: params[:enabled]) do
          on(:ok) do |changed|
            redirect_to settings_features_path(anchor: "feature-#{changed.name}"),
                        notice: changed.on? ? "#{changed.label} is on." : "#{changed.label} is off."
          end
          on(:not_installed) do |refused|
            redirect_to settings_features_path(anchor: "feature-#{refused.name}"),
                        alert: "#{refused.label} is not installed in this app yet."
          end
        end
      end
    end
  end
end
