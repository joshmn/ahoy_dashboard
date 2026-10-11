module AhoyDashboard
  module Settings
    module AiVisibilityAssistants
      class SecretsController < AhoyDashboard::BaseController
        requires_installed :ai_visibility

        def destroy
          name = params[:ai_visibility_assistant_name].to_s
          raise ActiveRecord::RecordNotFound unless removable?(name)

          secret = AhoyDashboard::Settings::StoredSecretPresenter.ai_visibility(name)
          back = edit_settings_ai_visibility_assistant_path(name)

          AhoyDashboard::AiVisibility::Keys::RemoveCommand.call(name: name) do
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
