module AhoyDashboard
  module SearchConsole
    # Hands the grant back to Google and drops the row. The rows already
    # collected stay: they are the local record of sixteen months Google will
    # not serve twice, and they have nothing to do with whether we can still ask
    # for more.
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
