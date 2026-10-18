module AhoyDashboard
  module Settings
    class GoogleCredentialsController < AhoyDashboard::Settings::BaseController
      requires_installed :search_console

      def update
        SearchConsole::Credentials::SaveCommand.call(values: credential_params) do
          on(:ok) { redirect_to settings_google_connection_path, notice: "Google API credentials saved." }
          on(:invalid) do |credential|
            redirect_to settings_google_connection_path, alert: credential.errors.full_messages.to_sentence
          end
        end
      end

      private

      def credential_params
        params.require(:google_credential).permit(*SearchConsole::CREDENTIAL_KEYS).to_h
      end
    end
  end
end
