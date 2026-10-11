module AhoyDashboard
  module Settings
    # Step one of the OAuth dance. Nothing is written here; the only side effect
    # is the state in the session, which is what the callback checks itself
    # against.
    class GoogleAuthorizationsController < AhoyDashboard::BaseController
      requires_installed :search_console

      STATE_KEY = :dash_google_state

      def new
        unless SearchConsole.enabled?
          return redirect_to settings_google_connection_path, alert: SearchConsole.unavailable_reason
        end

        if SearchConsole.redirect_uri.blank?
          return redirect_to settings_google_connection_path, alert: SearchConsole::NO_HOST_MESSAGE
        end

        session[STATE_KEY] = SecureRandom.urlsafe_base64(32)

        redirect_to SearchConsole.authorization_url(state: session[STATE_KEY]), allow_other_host: true
      end
    end
  end
end
