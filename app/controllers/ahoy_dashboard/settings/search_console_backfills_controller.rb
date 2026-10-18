module AhoyDashboard
  module Settings
    class SearchConsoleBackfillsController < AhoyDashboard::Settings::BaseController
      requires_installed :search_console

      def create
        refusal = SearchConsole.sync_refusal
        return refuse(refusal) if refusal

        SearchConsole::BackfillJob.perform_later

        redirect_to settings_google_connection_path,
                    notice: "Reaching back another month. Give it a minute, then reload."
      end

      private

      def refuse(message)
        redirect_to settings_google_connection_path, alert: message
      end
    end
  end
end
