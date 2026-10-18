module AhoyDashboard
  module Settings
    module GoogleCredentials
      class SecretsController < AhoyDashboard::Settings::BaseController
        requires_installed :search_console

        def destroy
          key = params[:key].to_s
          raise ActiveRecord::RecordNotFound unless SearchConsole::CREDENTIAL_KEYS.map(&:to_s).include?(key)

          secret = AhoyDashboard::Settings::StoredSecretPresenter.google(key)

          AhoyDashboard::Secrets::RemoveCommand.call(record: SearchConsole.credential, key: key) do
            on(:ok) { redirect_to settings_google_connection_path, notice: secret.removed_notice }
            on(:missing) { redirect_to settings_google_connection_path, alert: secret.missing_notice }
          end
        end
      end
    end
  end
end
