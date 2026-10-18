module AhoyDashboard
  module Settings
    module AssistantProviders
      class SecretsController < AhoyDashboard::Settings::BaseController
        requires_installed :assistant

        def destroy
          name = AhoyDashboard::Assistant.reader_key(params[:assistant_provider_name])
          raise ActiveRecord::RecordNotFound unless removable?(name)

          secret = AhoyDashboard::Settings::StoredSecretPresenter.assistant(name)
          back = edit_settings_assistant_provider_path(name)

          record = AhoyDashboard::AssistantProvider.for(name)

          AhoyDashboard::Secrets::RemoveCommand.call(record: record, key: :api_key) do
            on(:ok) { redirect_to back, notice: secret.removed_notice }
            on(:missing) { redirect_to back, alert: secret.missing_notice }
          end
        end

        private

        def removable?(name)
          AhoyDashboard::AssistantProvider::NAMES.include?(name) && params[:key] == "api_key"
        end
      end
    end
  end
end
