module AhoyDashboard
  module Serp
    class ProviderForm < AhoyDashboard::Form
      FIELDS = %i[name monthly_cap_units active credentials].freeze

      attribute :name, :string
      attribute :monthly_cap_units, :integer, default: 500
      attribute :active, :boolean, default: false
      attribute :credentials

      validates :name, inclusion: { in: SerpProvider::NAMES, message: "is not an adapter this has" }
      validates :monthly_cap_units, numericality: {
        only_integer: true, greater_than_or_equal_to: 0,
        message: "has to be a whole number of searches, or zero for no ceiling"
      }

      def self.from_record(provider)
        new(name: provider.name, monthly_cap_units: provider.monthly_cap_units,
            active: provider.active, credentials: provider.credentials)
      end

      def credential_keys
        return [] if name.blank? || SerpProvider::NAMES.exclude?(name)

        Serp.adapter_class(name).credential_keys
      end

      def credential(key)
        (credentials || {}).to_h.symbolize_keys[key.to_sym]
      end

      def submitted_credentials
        (credentials || {}).to_h.symbolize_keys.slice(*credential_keys)
      end
    end
  end
end
