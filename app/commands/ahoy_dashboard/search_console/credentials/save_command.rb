module AhoyDashboard
  module SearchConsole
    module Credentials
      class SaveCommand < AhoyDashboard::Command
        def initialize(values:)
          @values = values
        end

        def call
          credential = AhoyDashboard::Credential.fetch(CREDENTIAL_NAME)
          credential.credentials = credential.credentials.merge(submitted)
          return broadcast(:invalid, credential) unless credential.save

          broadcast(:ok, credential)
        end

        private

        attr_reader :values

        def submitted
          values.to_h.symbolize_keys.transform_values { |value| value.to_s.strip.presence }.compact
        end
      end
    end
  end
end
