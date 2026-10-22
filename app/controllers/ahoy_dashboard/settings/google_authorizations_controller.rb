module AhoyDashboard
  module Settings
    class GoogleAuthorizationsController < AhoyDashboard::Settings::BaseController
      requires_installed :search_console

      STATE_KEY = :dash_google_state

      def new
        unless SearchConsole.enabled?
          return redirect_to settings_google_connection_path, alert: SearchConsole.unavailable_reason
        end

        if SearchConsole.redirect_uri.blank?
          return redirect_to settings_google_connection_path, alert: SearchConsole::NO_HOST_MESSAGE
        end

        state = SecureRandom.urlsafe_base64(32)
        session[dashboard_key(STATE_KEY)] = state

        redirect_to SearchConsole.authorization_url(state: state), allow_other_host: true
      end
    end
  end
end
