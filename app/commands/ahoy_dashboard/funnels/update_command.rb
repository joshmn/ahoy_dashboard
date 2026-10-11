module AhoyDashboard
  module Funnels
    class UpdateCommand < AhoyDashboard::Command
      def initialize(funnel:, form:)
        @funnel = funnel
        @form = form
      end

      # A savepoint rather than a joined transaction, because the old steps are
      # deleted before the new ones are known to be good. Without one, a rename the
      # record refuses would leave the funnel with no steps at all.
      def call
        return broadcast(:invalid, form) if form.invalid?

        AhoyDashboard::Funnel.transaction(requires_new: true) do
          funnel.assign_attributes(form.record_attributes)
          replace_steps
          funnel.save!
        end

        broadcast(:ok, funnel)
      rescue ActiveRecord::RecordInvalid
        copy_errors
      rescue ActiveRecord::RecordNotUnique
        form.errors.add(:base, AhoyDashboard::FunnelForm::DUPLICATE_MESSAGE)
        broadcast(:duplicate, form)
      end

      private

      attr_reader :funnel, :form

      # The submitted list is the whole truth about the steps, so the old rows go
      # and the new ones are numbered from one. Left alone when the goals and their
      # order have not moved, so renaming a funnel does not churn its steps.
      def replace_steps
        return if funnel.funnel_steps.map(&:goal_id) == form.goal_ids

        funnel.funnel_steps.destroy_all
        form.goal_ids.each_with_index do |goal_id, index|
          funnel.funnel_steps.build(goal_id: goal_id, position: index + 1)
        end
      end

      def copy_errors
        funnel.errors.messages.each do |attribute, messages|
          messages.each { |message| form.errors.add(attribute, message) }
        end

        broadcast(:invalid, form)
      end
    end
  end
end
