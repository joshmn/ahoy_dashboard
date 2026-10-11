module AhoyDashboard
  module SearchConsole
    module Properties
      class SelectCommand < AhoyDashboard::Command
        def initialize(account:, form:)
          @account = account
          @form = form
        end

        def call
          return broadcast(:missing) if account.nil?
          return broadcast(:invalid, form) if form.invalid?

          cleared = nil

          GoogleAccount.transaction do
            events = Properties::AdoptCommand.call(account: account, property_uri: form.property_uri)
            cleared = events[:cleared]

            # Stored exactly as Google handed it over. "sc-domain:example.com" is the
            # real identifier of a domain property, not a scheme that needs fixing.
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
