module AhoyDashboard
  module Funnels
    class CreateCommand < AhoyDashboard::Command
      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        funnel = AhoyDashboard::Funnel.new(form.record_attributes.merge(position: AhoyDashboard::Funnel.next_position))
        funnel.funnel_steps.build(form.step_attributes)
        return broadcast(:invalid, form.copy_errors_from(funnel)) unless funnel.save

        broadcast(:ok, funnel)
      rescue ActiveRecord::RecordNotUnique
        form.add_duplicate_error
        broadcast(:invalid, form)
      end

      private

      attr_reader :form
    end
  end
end
