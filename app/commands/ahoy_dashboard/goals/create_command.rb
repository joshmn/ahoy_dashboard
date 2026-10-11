module AhoyDashboard
  module Goals
    # Two goals that differ only in display name are the same goal, and the unique
    # null-safe unique index over the definition says so. It is the database
    # that decides, so a collision arrives as RecordNotUnique rather than as a
    # validation failure and is answered here.
    class CreateCommand < AhoyDashboard::Command
      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        goal = AhoyDashboard::Goal.new(form.record_attributes.merge(position: next_position))
        return copy_errors(goal) unless goal.save

        broadcast(:ok, goal)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:base, AhoyDashboard::GoalForm::DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :form

      def next_position
        (AhoyDashboard::Goal.maximum(:position) || 0) + 1
      end

      def copy_errors(goal)
        goal.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
