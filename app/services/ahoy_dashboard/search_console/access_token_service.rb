module AhoyDashboard
  module SearchConsole
    # The only way anything else gets a token. Hands back one that is good right
    # now, refreshing first when the stored one is spent or unreadable.
    class AccessTokenService < BaseService
      def initialize(account: nil)
        @account = account || GoogleAccount.current
      end

      def call
        raise AuthError, "google is not connected" unless account&.connected?
        return account.access_token if usable?

        RefreshTokenService.call(account: account)
      end

      private

      attr_reader :account

      # A token stored under a rotated secret_key_base reads back as nil, which
      # is a refresh rather than a failure.
      def usable?
        account.access_token.present? && !account.expired?
      end
    end
  end
end
