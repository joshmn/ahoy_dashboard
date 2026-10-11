module AhoyDashboard
  module SearchConsole
    # Turns the code Google put in the callback into the one stored account.
    #
    # One admin, so one row: an existing row is updated rather than a second one
    # added, and a reconnect keeps the property that was already picked so the
    # nightly job carries on without another trip through the picker.
    class ConnectCommand < AhoyDashboard::Command
      def initialize(code:)
        @code = code
      end

      def call
        return broadcast(:unavailable, "search console is not configured") unless SearchConsole.enabled?

        account = store(ExchangeCodeService.call(code: code))

        # A first connect with no refresh token in the answer leaves nothing the
        # nightly job can use, so it is a refusal rather than a connection.
        return broadcast(:refused, "google returned no refresh token") unless account.connected?

        broadcast(:ok, account)
      rescue AuthError => e
        broadcast(:refused, e.message)
      rescue Error => e
        broadcast(:failed, e.message)
      end

      private

      attr_reader :code

      def store(tokens)
        account = GoogleAccount.current || GoogleAccount.new

        account.access_token = tokens.access_token
        account.refresh_token = tokens.refresh_token
        account.expires_at = tokens.expires_at
        account.scope = tokens.scope
        account.connected_at = Time.current
        account.save!
        account.clear_error!
        account
      end
    end
  end
end
