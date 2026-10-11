# frozen_string_literal: true

module AhoyDashboard

  module SearchConsole

    class PageContext
      attr_reader :account, :countries, :stored_span

      def initialize(account: nil, countries: [], stored_span: nil)
        @account = account
        @countries = countries
        @stored_span = stored_span
      end

      def connected?
        account && account.ready? || false
      end
    end
  end
end
