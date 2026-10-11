module AhoyDashboard
  module Settings
    class GoogleConnectionsController < AhoyDashboard::BaseController
      requires_installed :search_console

      include AhoyDashboard::SearchConsoleScreen

      def show
        load_search_console_screen
      end

      def destroy
        SearchConsole::DisconnectCommand.call do
          on(:ok) { redirect_to settings_google_connection_path, notice: "Google is disconnected." }
          on(:missing) { redirect_to settings_google_connection_path, alert: "There was nothing connected." }
        end
      end
    end
  end
end
