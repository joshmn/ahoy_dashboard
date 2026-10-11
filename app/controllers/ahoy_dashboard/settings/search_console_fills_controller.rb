module AhoyDashboard
  module Settings
    # Closing the holes in the middle of the record. Its own resource beside the
    # sync and the backfill because it is a third thing: the sync keeps the top
    # of the record current, the backfill extends the bottom, and this one goes
    # back for days both of them have already walked past.
    class SearchConsoleFillsController < AhoyDashboard::BaseController
      requires_installed :search_console

      def create
        account = GoogleAccount.current

        return refuse(SearchConsole.unavailable_reason) unless SearchConsole.enabled?
        return refuse("Connect Google first.") unless account&.connected?
        return refuse("Pick a property first.") unless account.property_selected?

        running = SearchConsole::FillQueue.load
        return refuse("A fill is already going. #{running.note}") if running.running?

        start(SearchConsoleMissingDaysQuery.call.dates)
      end

      private

      # The list is built here rather than in the job, because what the page
      # offered to fill is what gets filled. A job that read the holes fresh
      # would go after days that were nowhere on the screen when the button was
      # pressed.
      def start(dates)
        return refuse("Nothing is missing. Every day Google still serves is here.") if dates.empty?

        SearchConsole::FillQueue.start!(dates)
        SearchConsole::FillJob.perform_later

        redirect_to settings_google_connection_path,
                    notice: "Filling #{dates.size} #{"day".pluralize(dates.size)}, oldest first. " \
                            "Give it a minute, then reload."
      end

      def refuse(message)
        redirect_to settings_google_connection_path, alert: message
      end
    end
  end
end
