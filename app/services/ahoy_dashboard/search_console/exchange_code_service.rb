module AhoyDashboard
  module SearchConsole
    # The one-time swap of the code Google put in the callback URL for a pair of
    # tokens. Returns them and saves nothing; the command decides what to keep.
    class ExchangeCodeService < BaseService
      DEFAULT_LIFETIME = 3600

      Tokens = Data.define(:access_token, :refresh_token, :expires_at, :scope)

      def initialize(code:)
        @code = code
      end

      def call
        raise AuthError, "search console is not configured" unless SearchConsole.enabled?
        raise AuthError, "google sent no authorization code" if code.blank?

        payload = post_form(SearchConsole::TOKEN_URL, {
          code: code,
          client_id: SearchConsole.client_id,
          client_secret: SearchConsole.client_secret,
          redirect_uri: SearchConsole.redirect_uri,
          grant_type: "authorization_code"
        })

        raise AuthError, "google returned no access token" if payload["access_token"].blank?

        Tokens.new(
          access_token: payload["access_token"],
          refresh_token: payload["refresh_token"],
          expires_at: Time.current + lifetime(payload).seconds,
          scope: payload["scope"]
        )
      end

      private

      attr_reader :code

      def lifetime(payload)
        payload["expires_in"].presence&.to_i || DEFAULT_LIFETIME
      end
    end
  end
end
