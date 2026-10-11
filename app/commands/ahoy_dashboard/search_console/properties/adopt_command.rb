module AhoyDashboard
  module SearchConsole
    module Properties
      class AdoptCommand < AhoyDashboard::Command
        TABLES = [ SearchConsoleRow, SearchConsoleKeyword, SearchConsoleTotal ].freeze

        def initialize(property_uri:, account: nil)
          @account = account || GoogleAccount.current
          @property_uri = property_uri.to_s
        end

        def call
          return broadcast(:invalid) if property_uri.blank?

          owner = SearchConsole.stored_property || account&.property_uri.presence
          return keep if owner.blank? || owner == property_uri

          days = SearchConsoleTotal.distinct.count(:date)
          clear!
          broadcast(:cleared, days)
        end

        private

        attr_reader :account, :property_uri

        def keep
          SearchConsole.store_property!(property_uri) unless SearchConsole.stored_property == property_uri
          broadcast(:kept, property_uri)
        end

        def clear!
          SearchConsoleTotal.transaction do
            TABLES.each(&:delete_all)
            account&.update_columns(backfilled_to: nil, synced_at: nil, last_error: nil, last_error_at: nil)
            SearchConsole.store_property!(property_uri)
          end
        end
      end
    end
  end
end
