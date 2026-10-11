module AhoyDashboard
  module Properties
    # Switching a property off leaves the row alone and only stops the dashboard
    # offering it. Nothing about what is recorded changes either way, which is the
    # whole point of the list.
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
