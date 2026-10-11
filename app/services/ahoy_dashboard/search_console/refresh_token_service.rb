module AhoyDashboard
  module SearchConsole
    # Trades the refresh token for a fresh access token and stores it.
    #
    # The refresh response carries no refresh token of its own, which is normal.
    # GoogleAccount#refresh_token= ignores blanks for exactly that reason, so the
    # working one survives every refresh.
    class RefreshTokenService < BaseService
      DEFAULT_LIFETIME = 3600

      RECONNECT_MESSAGE = "Google refused the saved refresh token. Connect the account again. " \
                          "If this comes back every week, the Cloud project is still in testing.".freeze
      REFUSED_MESSAGE = "Google would not hand back an access token. Connect the account again.".freeze

      def initialize(account:)
        @account = account
      end

      def call
        raise AuthError, "search console is not configured" unless SearchConsole.enabled?
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
        account.expires_at = Time.current + lifetime(payload).seconds
        account.scope = payload["scope"] if payload["scope"].present?
        account.save!
        account.clear_error! if [ RECONNECT_MESSAGE, REFUSED_MESSAGE ].include?(account.last_error)
      end

      def lifetime(payload)
        payload["expires_in"].presence&.to_i || DEFAULT_LIFETIME
      end
    end
  end
end
