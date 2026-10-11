module AhoyDashboard
  module Goals
    class DestroyCommand < AhoyDashboard::Command
      def initialize(goal:)
        @goal = goal
      end

      # A goal a funnel is built on cannot be deleted: the foreign key restricts,
      # so this arrives as InvalidForeignKey rather than as a validation. Naming the
      # funnels is the whole point of catching it, because otherwise the refusal
      # tells somebody they cannot do a thing without saying what is stopping them.
      def call
        goal.destroy!

        broadcast(:ok, goal)
      rescue ActiveRecord::InvalidForeignKey
        broadcast(:in_use, goal, funnel_names)
      end

      private

      attr_reader :goal

      def funnel_names
        AhoyDashboard::Funnel.where(id: goal.funnel_steps.select(:funnel_id)).order(:position, :id).pluck(:name)
      end
    end
  end
end
