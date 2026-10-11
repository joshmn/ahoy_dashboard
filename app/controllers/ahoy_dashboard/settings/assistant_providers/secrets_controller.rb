module AhoyDashboard
  module Settings
    module AssistantProviders
      class SecretsController < AhoyDashboard::BaseController
        requires_installed :assistant

        def destroy
          name = params[:assistant_provider_name].to_s
          raise ActiveRecord::RecordNotFound unless removable?(name)

          secret = AhoyDashboard::Settings::StoredSecretPresenter.assistant(name)
          back = edit_settings_assistant_provider_path(name)

          AhoyDashboard::Assistant::Keys::RemoveCommand.call(name: name) do
            on(:ok) { redirect_to back, notice: secret.removed_notice }
            on(:missing) { redirect_to back, alert: secret.missing_notice }
          end
        end

        private

        def removable?(name)
          AhoyDashboard::AssistantProvider::NAMES.include?(name) && params[:key] == "api_key" &&
            AhoyDashboard::Assistant::READERS.fetch(name)[:local].blank?
        end
      end
    end
  end
end
