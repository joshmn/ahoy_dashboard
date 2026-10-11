module AhoyDashboard
  module Settings
    class EmailsController < AhoyDashboard::BaseController
      def edit
        @form = AhoyDashboard::EmailSettingsForm.current
      end

      def update
        @form = AhoyDashboard::EmailSettingsForm.new(email_params)

        AhoyDashboard::EmailSettings::UpdateCommand.call(form: @form) do
          on(:ok) { redirect_to edit_settings_emails_path, notice: "Saved." }
          on(:invalid) do |form|
            @form = form
            render :edit, status: :unprocessable_entity
          end
        end
      end

      private

      def email_params
        params.fetch(:emails, {}).permit(:alerts_recipients, :alerts_from, :alerts_send_empty,
                                         :reports_recipients, :reports_from,
                                         alerts_digest: [], reports_digest: [])
      end
    end
  end
end
