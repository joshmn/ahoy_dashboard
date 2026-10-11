module AhoyDashboard
  module Segments
    class DestroyCommand < AhoyDashboard::Command
      def initialize(segment:)
        @segment = segment
      end

      def call
        segment.destroy!

        broadcast(:ok, segment)
      end

      private

      attr_reader :segment
    end
  end
end
