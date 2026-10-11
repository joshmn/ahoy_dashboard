module AhoyDashboard
  module Funnels
    # Where a funnel sits in the list, which is the order the report picker offers
    # them in. Cosmetic, unlike a goal's position, which decides which goal claims
    # an event.
    class MoveCommand < AhoyDashboard::Command
      def initialize(funnel:, direction:)
        @funnel = funnel
        @direction = direction
      end

      def call
        moved = AhoyDashboard::ReorderListService.call(
          scope: AhoyDashboard::Funnel.ordered, moved: funnel, direction: direction
        )
        return broadcast(:nothing_to_do) if moved.nil?

        broadcast(:ok, funnel)
      end

      private

      attr_reader :funnel, :direction
    end
  end
end
