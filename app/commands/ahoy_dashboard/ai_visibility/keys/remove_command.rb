module AhoyDashboard
  module AiVisibility
    module Keys
      class RemoveCommand < AhoyDashboard::Command
        def initialize(name:)
          @name = name.to_s
        end

        def call
          assistant = Assistant.for(name)
          return broadcast(:missing) if assistant.nil? || assistant.api_key.blank?

          assistant.update!(credentials: assistant.credentials.except(:api_key))
          broadcast(:ok, assistant)
        end

        private

        attr_reader :name
      end
    end
  end
end
