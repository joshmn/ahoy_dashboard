module AhoyDashboard
  module Goals
    class DestroyCommand < AhoyDashboard::Command
      def initialize(goal:)
        @goal = goal
      end

      def call
        return broadcast(:in_use, goal, funnel_names) if goal.funnel_steps.exists?

        goal.destroy!

        broadcast(:ok, goal)
      rescue ActiveRecord::StatementInvalid => error
        raise unless restricted?(error)

        broadcast(:in_use, goal, funnel_names)
      end

      private

      attr_reader :goal

      def restricted?(error)
        error.is_a?(ActiveRecord::InvalidForeignKey) || error.cause.is_a?(PG::RestrictViolation)
      end

      def funnel_names
        AhoyDashboard::Funnel.where(id: goal.funnel_steps.select(:funnel_id)).order(:position, :id).pluck(:name)
      end
    end
  end
end
