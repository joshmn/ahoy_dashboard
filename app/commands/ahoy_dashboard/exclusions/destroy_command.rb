module AhoyDashboard
  module Exclusions
    class DestroyCommand < AhoyDashboard::Command
      def initialize(exclusion:)
        @exclusion = exclusion
      end

      def call
        exclusion.destroy!

        broadcast(:ok, exclusion)
      end

      private

      attr_reader :exclusion
    end
  end
end
