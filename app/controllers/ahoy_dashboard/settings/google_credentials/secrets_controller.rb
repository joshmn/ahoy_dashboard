module AhoyDashboard
  module Settings
    module GoogleCredentials
      class SecretsController < AhoyDashboard::BaseController
        requires_installed :search_console

        KEYS = %w[client_id client_secret].freeze

        def destroy
          key = params[:key].to_s
          raise ActiveRecord::RecordNotFound unless KEYS.include?(key)

          secret = AhoyDashboard::Settings::StoredSecretPresenter.google(key)

          AhoyDashboard::SearchConsole::Credentials::RemoveCommand.call(key: key) do
            on(:ok) { redirect_to settings_google_connection_path, notice: secret.removed_notice }
            on(:missing) { redirect_to settings_google_connection_path, alert: secret.missing_notice }
          end
        end
      end
    end
  end
end
