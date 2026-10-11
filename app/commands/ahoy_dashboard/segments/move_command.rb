module AhoyDashboard
  module Segments
    # Where a segment sits in the list, which is the order the filter dialog offers
    # them in and all it does. Unlike a goal's position, nothing about what a
    # segment counts changes with it.
    class MoveCommand < AhoyDashboard::Command
      def initialize(segment:, direction:)
        @segment = segment
        @direction = direction
      end

      def call
        moved = AhoyDashboard::ReorderListService.call(
          scope: AhoyDashboard::Segment.ordered, moved: segment, direction: direction
        )
        return broadcast(:nothing_to_do) if moved.nil?

        broadcast(:ok, segment)
      end

      private

      attr_reader :segment, :direction
    end
  end
end
