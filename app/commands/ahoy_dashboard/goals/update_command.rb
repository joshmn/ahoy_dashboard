module AhoyDashboard
  module Goals
    class UpdateCommand < AhoyDashboard::Command
      def initialize(goal:, form:)
        @goal = goal
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?
        return copy_errors unless goal.update(form.record_attributes)

        broadcast(:ok, goal)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:base, AhoyDashboard::GoalForm::DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :goal, :form

      def copy_errors
        goal.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
