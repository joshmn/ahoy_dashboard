module AhoyDashboard
  module Properties
    class DestroyCommand < AhoyDashboard::Command
      def initialize(property:)
        @property = property
      end

      def call
        property.destroy!

        broadcast(:ok, property)
      end

      private

      attr_reader :property
    end
  end
end
