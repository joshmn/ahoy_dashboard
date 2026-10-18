# frozen_string_literal: true

module AhoyDashboard

  module FunnelSteps

    class MoveCommand < AhoyDashboard::Command
      def initialize(funnel:, step_id:, direction:)
        @funnel = funnel
        @step_id = step_id
        @direction = direction
      end

      def call
        step = nil
        moved = funnel.with_lock do
          step = funnel.funnel_steps.reload.to_a.find { |candidate| candidate.id.to_s == step_id.to_s }
          next unless step

          AhoyDashboard::ReorderListService.call(scope: funnel.funnel_steps, moved: step, direction: direction,
                                                 unique: true)
        end
        return broadcast(:nothing_to_do) unless moved

        broadcast(:ok, step)
      end

      private

      attr_reader :funnel, :step_id, :direction
    end
  end
end
