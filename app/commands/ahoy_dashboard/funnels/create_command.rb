module AhoyDashboard
  module Funnels
    # The funnel and its steps are written together, because a funnel with no steps
    # is not a valid record and there is no half-built state worth saving.
    class CreateCommand < AhoyDashboard::Command
      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        funnel = AhoyDashboard::Funnel.new(form.record_attributes.merge(position: next_position))
        form.goal_ids.each_with_index do |goal_id, index|
          funnel.funnel_steps.build(goal_id: goal_id, position: index + 1)
        end

        return copy_errors(funnel) unless funnel.save

        broadcast(:ok, funnel)
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:base, AhoyDashboard::FunnelForm::DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :form

      def next_position
        (AhoyDashboard::Funnel.maximum(:position) || 0) + 1
      end

      def copy_errors(funnel)
        funnel.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
