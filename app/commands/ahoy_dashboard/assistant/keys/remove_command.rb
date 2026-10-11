module AhoyDashboard
  module Assistant
    module Keys
      class RemoveCommand < AhoyDashboard::Command
        def initialize(name:)
          @name = name.to_s
        end

        def call
          provider = AssistantProvider.for(name)
          return broadcast(:missing) if provider.nil? || provider.api_key.blank?

          provider.update!(credentials: provider.credentials.except(:api_key))
          broadcast(:ok, provider)
        end

        private

        attr_reader :name
      end
    end
  end
end
