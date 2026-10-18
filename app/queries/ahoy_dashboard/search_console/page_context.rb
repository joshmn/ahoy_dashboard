# frozen_string_literal: true

module AhoyDashboard

  module SearchConsole

    PageContext = Data.define(:account, :countries, :stored_span) do
      def initialize(account: nil, countries: [], stored_span: nil)
        super
      end

      def connected?
        account && account.ready? || false
      end
    end
  end
end
