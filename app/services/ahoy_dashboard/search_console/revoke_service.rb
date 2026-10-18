module AhoyDashboard
  module SearchConsole
    class RevokeService < BaseService
      def initialize(account:)
        @account = account
      end

      def call
        return false if account.nil?

        token = account.refresh_token.presence || account.access_token.presence
        return false if token.blank?

        post_form(SearchConsole::REVOKE_URL, { token: token })
        true
      rescue Error => e
        Rails.logger.warn "search console revoke failed: #{e.message}"
        false
      end

      private

      attr_reader :account
    end
  end
end
