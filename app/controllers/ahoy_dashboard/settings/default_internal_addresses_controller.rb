module AhoyDashboard
  module Settings
    class DefaultInternalAddressesController < AhoyDashboard::Settings::BaseController
      def create
        AhoyDashboard::GeneralSettings::RestoreInternalAddressesCommand.call do
          on(:ok) do
            redirect_to edit_settings_general_path(anchor: "internal-addresses"),
                        notice: "Internal addresses are back to the defaults."
          end
        end
      end
    end
  end
end
