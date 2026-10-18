module AhoyDashboard
  module Properties
    class UpdateCommand < AhoyDashboard::Command
      def initialize(property:, enabled:)
        @property = property
        @enabled = ActiveModel::Type::Boolean.new.cast(enabled)
      end

      def call
        property.update!(enabled: enabled)
        broadcast(:ok, property)
      end

      private

      attr_reader :property, :enabled
    end
  end
end
