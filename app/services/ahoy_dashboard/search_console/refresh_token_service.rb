module AhoyDashboard
  module SearchConsole
    class RefreshTokenService < BaseService
      RECONNECT_MESSAGE = "Google refused the saved refresh token. Connect the account again. " \
                          "If this comes back every week, the Cloud project is still in testing.".freeze
      REFUSED_MESSAGE = "Google would not hand back an access token. Connect the account again.".freeze

      def initialize(account:)
        @account = account
      end

      def call
        require_configured!
        raise AuthError, "google is not connected" unless account&.connected?

        store(refresh)
        account.access_token
      end

      private

      attr_reader :account

      def refresh
        payload = post_form(SearchConsole::TOKEN_URL, {
          client_id: SearchConsole.client_id,
          client_secret: SearchConsole.client_secret,
          refresh_token: account.refresh_token,
          grant_type: "refresh_token"
        })

        raise AuthError, "google returned no access token on refresh" if payload["access_token"].blank?

        payload
      rescue AuthError => e
        account.record_error!(e.reconnect_required? ? RECONNECT_MESSAGE : REFUSED_MESSAGE)
        raise
      end

      def store(payload)
        account.access_token = payload["access_token"]
        account.expires_at = expires_at(payload)
        account.scope = payload["scope"] if payload["scope"].present?
        account.save!
        account.clear_error! if [ RECONNECT_MESSAGE, REFUSED_MESSAGE ].include?(account.last_error)
      end
    end
  end
end
