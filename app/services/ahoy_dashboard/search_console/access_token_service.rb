module AhoyDashboard
  module SearchConsole
    class AccessTokenService < BaseService
      def initialize(account: nil)
        @account = account || GoogleAccount.current
      end

      def call
        raise AuthError, "google is not connected" unless account&.connected?

        token = account.access_token
        return token if token.present? && !account.expired?

        RefreshTokenService.call(account: account)
      end

      private

      attr_reader :account
    end
  end
end
