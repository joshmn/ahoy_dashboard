module AhoyDashboard
  module DefaultSegments
    class MakeCommand < AhoyDashboard::Command
      def initialize(segment:)
        @segment = segment
      end

      def call
        return broadcast(:unreadable, segment) unless segment.readable?

        AhoyDashboard::Segment.transaction do
          AhoyDashboard::Segment.where(applied_by_default: true).where.not(id: segment.id)
                                .update_all(applied_by_default: false)
          segment.update_columns(applied_by_default: true)
        end

        broadcast(:ok, segment)
      end

      private

      attr_reader :segment
    end
  end
end
