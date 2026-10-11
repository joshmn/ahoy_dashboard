module AhoyDashboard
  module Goals
    # Order decides which goal claims an event that two goals could both describe,
    # because Goal.match_case_sql is a case expression and the first match wins. So
    # this is not only cosmetic.
    class MoveCommand < AhoyDashboard::Command
      def initialize(goal:, direction:)
        @goal = goal
        @direction = direction
      end

      def call
        moved = AhoyDashboard::ReorderListService.call(
          scope: AhoyDashboard::Goal.ordered, moved: goal, direction: direction
        )
        return broadcast(:nothing_to_do) if moved.nil?

        broadcast(:ok, goal)
      end

      private

      attr_reader :goal, :direction
    end
  end
end
