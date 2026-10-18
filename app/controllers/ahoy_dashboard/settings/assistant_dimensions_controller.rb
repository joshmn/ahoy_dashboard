module AhoyDashboard
  module Settings
    class AssistantDimensionsController < AhoyDashboard::Settings::BaseController
      requires_installed :assistant

      def edit
        @form = AhoyDashboard::Assistant::WithheldDimensionsForm.current
      end

      def update
        @form = AhoyDashboard::Assistant::WithheldDimensionsForm.new(keys: dimension_params)

        AhoyDashboard::Assistant::WithheldDimensions::SaveCommand.call(form: @form) do
          on(:ok) { redirect_to settings_assistant_providers_path, notice: "Saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      private

      def dimension_params
        params.fetch(:assistant_dimensions, {}).permit(keys: [])[:keys] || []
      end
    end
  end
end
