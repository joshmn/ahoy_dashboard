module AhoyDashboard
  module Settings
    module Exclusions
      class StatesController < AhoyDashboard::Settings::BaseController
        def update
          exclusion = AhoyDashboard::Exclusion.find(params[:exclusion_id])

          AhoyDashboard::Exclusions::ToggleCommand.call(exclusion: exclusion, enabled: params[:enabled].presence) do
            on(:ok) do |changed|
              redirect_to settings_exclusions_path,
                          notice: changed.enabled ? "#{changed.name} is on." : "#{changed.name} is off."
            end
            on(:nothing_to_do) { redirect_to settings_exclusions_path }
            on(:invalid) do |refused|
              redirect_to settings_exclusions_path,
                          alert: "#{refused.name} can't be turned on until its filters are fixed."
            end
          end
        end
      end
    end
  end
end
