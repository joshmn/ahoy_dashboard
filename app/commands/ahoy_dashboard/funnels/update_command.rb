module AhoyDashboard
  module Funnels
    class UpdateCommand < AhoyDashboard::Command
      def initialize(funnel:, form:)
        @funnel = funnel
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        AhoyDashboard::Funnel.transaction(requires_new: true) do
          funnel.assign_attributes(form.record_attributes)
          replace_steps
          funnel.save!
        end

        broadcast(:ok, funnel)
      rescue ActiveRecord::RecordInvalid
        broadcast(:invalid, form.copy_errors_from(funnel))
      rescue ActiveRecord::RecordNotUnique
        form.add_duplicate_error
        broadcast(:invalid, form)
      end

      private

      attr_reader :funnel, :form

      def replace_steps
        return if funnel.funnel_steps.map(&:goal_id) == form.goal_ids

        funnel.funnel_steps.destroy_all
        funnel.funnel_steps.build(form.step_attributes)
      end
    end
  end
end
