module AhoyDashboard
  module Settings
    class AiVisibilitiesController < AhoyDashboard::Settings::BaseController
      requires_installed :ai_visibility

      def edit
        @form = AhoyDashboard::AiVisibility::SettingsForm.current
        set_overview
      end

      def update
        @form = AhoyDashboard::AiVisibility::SettingsForm.new(settings_params)

        AhoyDashboard::AiVisibility::Settings::SaveCommand.call(form: @form) do
          on(:ok) { redirect_to edit_settings_ai_visibility_path, notice: "AI visibility saved." }
          on(:invalid) do |form|
            set_overview
            rejected(form)
          end
          on(:confirm_deletions) do |form, stake|
            @form = form
            @at_stake = stake
            set_overview
            render :edit
          end
        end
      end

      private

      def set_overview
        @names = AhoyDashboard::AiVisibility::NAMES
        @records = AhoyDashboard::AiVisibility.records
        @used = AhoyDashboard::AiVisibility.used_this_month
        @prompt_count = AhoyDashboard::AiVisibility::Prompt.count
        @targets = AhoyDashboard::AiVisibility.targets(@records).size
      end

      def settings_params
        params.require(:ai_visibility).permit(:prompts, :frequency, :monthly_cap, :confirm)
      end
    end
  end
end
