module AhoyDashboard
  module SearchConsole
    module Credentials
      class RemoveCommand < AhoyDashboard::Command
        def initialize(key:)
          @key = key.to_sym
        end

        def call
          credential = SearchConsole.credential
          return broadcast(:missing) if credential.nil? || credential.value(key).blank?

          credential.update!(values: credential.values.except(key))
          broadcast(:ok, credential)
        end

        private

        attr_reader :key
      end
    end
  end
end
