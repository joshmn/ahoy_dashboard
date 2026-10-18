module AhoyDashboard
  module Settings
    class SearchConsolePropertiesController < AhoyDashboard::Settings::BaseController
      requires_installed :search_console

      before_action :set_account!
      before_action :set_stored

      def edit
        @form = SearchConsole::PropertyForm.new(sites: sites, property_uri: @account.property_uri)
      rescue SearchConsole::Error => e
        redirect_to settings_google_connection_path, alert: unreachable(e)
      end

      def update
        @form = SearchConsole::PropertyForm.new(sites: sites, **property_params)

        SearchConsole::Properties::SelectCommand.call(account: @account, form: @form) do
          on(:ok) { redirect_to settings_google_connection_path, notice: "Search Console property saved." }
          on(:switched) { |_account, days| redirect_to settings_google_connection_path, notice: switched_notice(days) }
          on(:invalid) { render :edit, status: 422 }
        end
      rescue SearchConsole::Error => e
        redirect_to settings_google_connection_path, alert: unreachable(e)
      end

      private

      def set_account!
        @account = GoogleAccount.current
        return if @account&.connected?

        redirect_to settings_google_connection_path,
                    alert: "Connect a Google account before picking a property."
      end

      def set_stored
        @stored_property = SearchConsole.stored_property || @account.property_uri.presence
        @stored_days = @stored_property ? SearchConsoleTotal.distinct.count(:date) : 0
      end

      def sites
        SearchConsole::SitesService.call(account: @account)
      end

      def property_params
        params.fetch(:property, {}).permit(:property_uri).to_h.symbolize_keys
      end

      def switched_notice(days)
        return "Search Console property saved. History for it starts pulling on the next run." if days.zero?

        "Search Console property saved. Removed #{helpers.pluralize(days, "day")} pulled for the old property. " \
          "History for this one starts pulling on the next run."
      end

      def unreachable(error)
        return "Google will not answer for this account any more. Connect it again." if error.is_a?(SearchConsole::AuthError)
        return "Google says this account is not allowed to list Search Console properties. Connect it again." if error.is_a?(SearchConsole::PermissionError)

        "Google did not answer, so the list of properties is not available right now."
      end
    end
  end
end
