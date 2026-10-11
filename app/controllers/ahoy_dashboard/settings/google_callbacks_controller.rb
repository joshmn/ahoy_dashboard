module AhoyDashboard
  module Settings
    # Where Google sends the browser back to. A GET, because that is all Google
    # does, so there is no CSRF token to check. The state is what stands in for
    # one: it was made in the session that started the redirect, and a request
    # that cannot produce it is refused rather than sent back to Google to try
    # again, because a retry loop is exactly what an attacker would want.
    class GoogleCallbacksController < AhoyDashboard::BaseController
      requires_installed :search_console

      def show
        expected = session.delete(GoogleAuthorizationsController::STATE_KEY)

        return refuse("That did not come back from a sign-in this browser started.") unless valid_state?(expected)
        return refuse(refusal_for(params[:error])) if params[:error].present?

        connect
      end

      private

      def valid_state?(expected)
        given = params[:state].to_s
        return false if expected.blank? || given.blank?

        ActiveSupport::SecurityUtils.secure_compare(given, expected)
      end

      def connect
        SearchConsole::ConnectCommand.call(code: params[:code]) do
          on(:ok) { redirect_to next_step, notice: "Google is connected." }
          on(:refused) { |message| refuse("Google turned the sign-in down. #{message}") }
          on(:unavailable) { |message| refuse(message) }
          on(:failed) { |message| refuse("Google did not finish the sign-in. #{message}") }
        end
      end

      # A first connection has no property yet, and the sync does nothing without
      # one, so the picker is the next screen rather than the status page.
      def next_step
        account = GoogleAccount.current

        if account&.property_selected?
          settings_google_connection_path
        else
          edit_settings_search_console_property_path
        end
      end

      def refuse(message)
        redirect_to settings_google_connection_path, alert: message
      end

      def refusal_for(error)
        return "You turned the request down, so nothing changed." if error == "access_denied"

        "Google refused the request: #{error}."
      end
    end
  end
end
