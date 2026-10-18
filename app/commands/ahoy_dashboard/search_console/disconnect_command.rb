module AhoyDashboard
  module SearchConsole
    class DisconnectCommand < AhoyDashboard::Command
      def initialize(account: nil)
        @account = account || GoogleAccount.current
      end

      def call
        return broadcast(:missing) if account.nil?

        revoked = RevokeService.call(account: account)
        account.destroy!
        broadcast(:ok, revoked)
      end

      private

      attr_reader :account
    end
  end
end
