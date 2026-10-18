module AhoyDashboard
  module SearchConsole
    module Properties
      class SelectCommand < AhoyDashboard::Command
        def initialize(account:, form:)
          @account = account
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          cleared = nil

          GoogleAccount.transaction do
            events = Properties::AdoptCommand.call(account: account, property_uri: form.property_uri)
            cleared = events[:cleared]

            account.update!(property_uri: form.property_uri)
          end

          return broadcast(:switched, account, cleared) if cleared

          broadcast(:ok, account)
        end

        private

        attr_reader :account, :form
      end
    end
  end
end
