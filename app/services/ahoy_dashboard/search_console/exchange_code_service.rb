module AhoyDashboard
  module SearchConsole
    class ExchangeCodeService < BaseService
      Tokens = Data.define(:access_token, :refresh_token, :expires_at, :scope)

      def initialize(code:)
        @code = code
      end

      def call
        require_configured!
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
          expires_at: expires_at(payload),
          scope: payload["scope"]
        )
      end

      private

      attr_reader :code
    end
  end
end
