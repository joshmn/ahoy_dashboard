module AhoyDashboard
  module Properties
    # Which property the card opens on is whichever one is first, so this is the
    # operator's only lever over that.
    class MoveCommand < AhoyDashboard::Command
      def initialize(property:, direction:)
        @property = property
        @direction = direction
      end

      def call
        moved = AhoyDashboard::ReorderListService.call(
          scope: AhoyDashboard::Property.ordered, moved: property, direction: direction
        )
        return broadcast(:nothing_to_do) if moved.nil?

        broadcast(:ok, property)
      end

      private

      attr_reader :property, :direction
    end
  end
end
