module AhoyDashboard
  module SavedQueries
    # Where a saved question sits in the list, which is the order the pinned ones sit in on the dashboard and all it does.
    class MoveCommand < AhoyDashboard::Command
      def initialize(record:, direction:)
        @record = record
        @direction = direction
      end

      def call
        moved = AhoyDashboard::ReorderListService.call(
          scope: AhoyDashboard::SavedQuery.ordered, moved: record, direction: direction
        )
        return broadcast(:nothing_to_do) if moved.nil?

        broadcast(:ok, record)
      end

      private

      attr_reader :record, :direction
    end
  end
end
