module AhoyDashboard
  module PageGroups
    # Where a rule sits in the list, which is which rule wins when a path matches two of them and all it does.
    class MoveCommand < AhoyDashboard::Command
      def initialize(record:, direction:)
        @record = record
        @direction = direction
      end

      def call
        moved = AhoyDashboard::ReorderListService.call(
          scope: AhoyDashboard::PageGroup.ordered, moved: record, direction: direction
        )
        return broadcast(:nothing_to_do) if moved.nil?

        broadcast(:ok, record)
      end

      private

      attr_reader :record, :direction
    end
  end
end
