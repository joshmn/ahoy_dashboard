module AhoyDashboard
  module Settings
    class GeneralsController < AhoyDashboard::Settings::BaseController
      def edit
        @form = AhoyDashboard::GeneralSettingsForm.current(request_host: request.host)
      end

      def update
        @form = AhoyDashboard::GeneralSettingsForm.new(general_params)

        AhoyDashboard::GeneralSettings::UpdateCommand.call(form: @form) do
          on(:ok) { redirect_to edit_settings_general_path, notice: "Saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      private

      def general_params
        params.fetch(:general, {}).permit(:time_zone, :host, :canonical_host, :internal_ips, :hide_known_crawlers,
                                              :precomputed_dashboard)
      end
    end
  end
end
