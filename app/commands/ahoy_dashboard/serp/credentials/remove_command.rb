module AhoyDashboard
  module Serp
    module Credentials
      class RemoveCommand < AhoyDashboard::Command
        def initialize(name:, key:)
          @name = name.to_s
          @key = key.to_sym
        end

        def call
          provider = SerpProvider.for(name)
          return broadcast(:missing) if provider.nil? || provider.credential(key).blank?

          provider.update!(credentials: provider.credentials.except(key))
          broadcast(:ok, provider)
        end

        private

        attr_reader :name, :key
      end
    end
  end
end
