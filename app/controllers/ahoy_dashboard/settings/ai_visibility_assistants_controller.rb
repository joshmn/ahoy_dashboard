module AhoyDashboard
  module Settings
    class AiVisibilityAssistantsController < AhoyDashboard::Settings::BaseController
      requires_installed :ai_visibility

      before_action :set_name
      before_action :set_secret

      def edit
        @form = AhoyDashboard::AiVisibility::AssistantForm.from_record(record)
      end

      def update
        @form = AhoyDashboard::AiVisibility::AssistantForm.new(assistant_params.merge(name: @name))

        AhoyDashboard::AiVisibility::Assistants::SaveCommand.call(form: @form) do
          on(:ok) { redirect_to edit_settings_ai_visibility_path, notice: "#{@form.label} saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      private

      def set_name
        @name = params[:name].to_s
        raise ActiveRecord::RecordNotFound unless AhoyDashboard::AiVisibility::NAMES.include?(@name)
      end

      def set_secret
        @secret = AhoyDashboard::Settings::StoredSecretPresenter.ai_visibility(@name)
        @removing = @secret if @secret.removing?(params[:remove])
      end

      def record
        AhoyDashboard::AiVisibility::Assistant.for(@name) || AhoyDashboard::AiVisibility::Assistant.new(name: @name)
      end

      def assistant_params
        permitted = params.require(:ai_visibility_assistant).permit(:enabled, :other_models, models: [])

        permitted.merge(credentials: params.require(:ai_visibility_assistant).fetch(:credentials, {}).permit(:api_key).to_h)
      end
    end
  end
end
