module AhoyDashboard
  module DefaultSegments
    class ClearCommand < AhoyDashboard::Command
      def initialize(segment: nil)
        @segment = segment
      end

      def call
        cleared = marked.update_all(applied_by_default: false)

        cleared.zero? ? broadcast(:nothing_to_do) : broadcast(:ok)
      end

      private

      attr_reader :segment

      def marked
        relation = AhoyDashboard::Segment.where(applied_by_default: true)

        segment ? relation.where(id: segment.id) : relation
      end
    end
  end
end
