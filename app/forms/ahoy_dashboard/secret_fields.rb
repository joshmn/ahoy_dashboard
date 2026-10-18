module AhoyDashboard
  module SecretFields
    extend ActiveSupport::Concern

    included do
      attribute :credentials
    end

    def credential_keys
      [ :api_key ]
    end

    def submitted_credentials
      (credentials || {}).to_h.symbolize_keys.slice(*credential_keys).reject { |_key, value| value.to_s.strip.blank? }
    end
  end
end
