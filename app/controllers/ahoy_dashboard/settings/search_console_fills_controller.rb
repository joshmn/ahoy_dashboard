module AhoyDashboard
  module Settings
    class SearchConsoleFillsController < AhoyDashboard::Settings::BaseController
      requires_installed :search_console

      def create
        refusal = SearchConsole.sync_refusal
        return refuse(refusal) if refusal

        running = SearchConsole::FillQueue.load
        return refuse("A fill is already going. #{running.note}") if running.running?

        start(SearchConsoleMissingDaysQuery.call.dates)
      end

      private

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
