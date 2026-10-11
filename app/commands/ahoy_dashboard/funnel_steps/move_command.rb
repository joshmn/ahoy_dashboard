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
        funnel.with_lock do
          steps = funnel.funnel_steps.reload.to_a
          step = steps.find { |candidate| candidate.id.to_s == step_id.to_s }
          return broadcast(:nothing_to_do) unless step

          moved = AhoyDashboard::ReorderService.call(records: steps, moved: step, direction: direction)
          return broadcast(:nothing_to_do) unless moved

          offset = steps.map(&:position).max
          moved.each_with_index { |listed, index| listed.update_column(:position, offset + index + 1) }
          moved.each_with_index { |listed, index| listed.update_column(:position, index + 1) }
        end
        broadcast(:ok, step)
      end

      private

      attr_reader :funnel, :step_id, :direction
    end
  end
end
