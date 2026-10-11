module AhoyDashboard
  module Settings
    # The manual pull. Enqueued rather than run inline: seven days of paged
    # requests is not something to hold a browser open for, and the nightly job
    # does the identical work.
    class SearchConsoleSyncsController < AhoyDashboard::BaseController
      requires_installed :search_console

      def create
        account = GoogleAccount.current

        return refuse(SearchConsole.unavailable_reason) unless SearchConsole.enabled?
        return refuse("Connect Google first.") unless account&.connected?
        return refuse("Pick a property first.") unless account.property_selected?

        SearchConsole::IngestJob.perform_later

        redirect_to settings_google_connection_path,
                    notice: "Pulling the last week from Search Console. Give it a minute, then reload."
      end

      private

      def refuse(message)
        redirect_to settings_google_connection_path, alert: message
      end
    end
  end
end
