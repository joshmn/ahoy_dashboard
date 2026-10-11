module AhoyDashboard
  module Settings
    class GoogleCredentialsController < AhoyDashboard::BaseController
      requires_installed :search_console

      def update
        credential = AhoyDashboard::Credential.fetch(SearchConsole::CREDENTIAL_NAME)
        credential.values = credential.values.merge(submitted_values)

        if credential.save
          redirect_to settings_google_connection_path, notice: "Google API credentials saved."
        else
          redirect_to settings_google_connection_path, alert: credential.errors.full_messages.to_sentence
        end
      end

      private

      # Blank fields keep whatever is already stored, same as a provider's
      # credentials form: this is the one screen the secret is ever typed
      # into, so leaving a field blank on a later edit must not clear it.
      def submitted_values
        params.require(:google_credential).permit(:client_id, :client_secret).to_h
          .transform_values { |value| value.to_s.strip.presence }.compact
      end
    end
  end
end
