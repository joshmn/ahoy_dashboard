module AhoyDashboard
  module Exclusions
    class ToggleCommand < AhoyDashboard::Command
      def initialize(exclusion:, enabled: nil)
        @exclusion = exclusion
        @enabled = enabled
      end

      def call
        wanted = enabled.nil? ? !exclusion.enabled : ActiveModel::Type::Boolean.new.cast(enabled)
        return broadcast(:nothing_to_do, exclusion) if wanted == exclusion.enabled
        return broadcast(:invalid, exclusion) if wanted && !exclusion.readable?

        exclusion.update_attribute(:enabled, wanted)

        broadcast(:ok, exclusion)
      end

      private

      attr_reader :exclusion, :enabled
    end
  end
end
