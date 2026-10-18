module AhoyDashboard
  module Settings
    module AiVisibilityAssistants
      class SecretsController < AhoyDashboard::Settings::BaseController
        requires_installed :ai_visibility

        def destroy
          name = params[:ai_visibility_assistant_name].to_s
          raise ActiveRecord::RecordNotFound unless removable?(name)

          secret = AhoyDashboard::Settings::StoredSecretPresenter.ai_visibility(name)
          back = edit_settings_ai_visibility_assistant_path(name)

          record = AhoyDashboard::AiVisibility::Assistant.for(name)

          AhoyDashboard::Secrets::RemoveCommand.call(record: record, key: :api_key) do
            on(:ok) { redirect_to back, notice: secret.removed_notice }
            on(:missing) { redirect_to back, alert: secret.missing_notice }
          end
        end

        private

        def removable?(name)
          AhoyDashboard::AiVisibility::NAMES.include?(name) && params[:key] == "api_key"
        end
      end
    end
  end
end
