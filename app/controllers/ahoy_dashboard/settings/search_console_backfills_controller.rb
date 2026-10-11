module AhoyDashboard
  module Settings
    # Walking the history backwards a month at a time. Its own resource rather
    # than a mode of the sync above it: that one re-reads the last week and is
    # what keeps the dashboard current, this one reaches for days Google is
    # about to stop serving at all, and they are never the same request.
    class SearchConsoleBackfillsController < AhoyDashboard::BaseController
      requires_installed :search_console

      def create
        account = GoogleAccount.current

        return refuse(SearchConsole.unavailable_reason) unless SearchConsole.enabled?
        return refuse("Connect Google first.") unless account&.connected?
        return refuse("Pick a property first.") unless account.property_selected?

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
