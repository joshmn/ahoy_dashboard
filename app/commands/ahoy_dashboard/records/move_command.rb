module AhoyDashboard
  module Records
    class MoveCommand < AhoyDashboard::Command
      def initialize(record:, direction:)
        @record = record
        @direction = direction
      end

      def call
        moved = AhoyDashboard::ReorderListService.call(scope: record.class.ordered, moved: record, direction: direction)
        return broadcast(:nothing_to_do) if moved.nil?

        broadcast(:ok, record)
      end

      private

      attr_reader :record, :direction
    end
  end
end
