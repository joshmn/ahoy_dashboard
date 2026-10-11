module AhoyDashboard
  module PageGroups
    class DestroyCommand < AhoyDashboard::Command
      def initialize(record:)
        @record = record
      end

      def call
        record.destroy!

        broadcast(:ok, record)
      end

      private

      attr_reader :record
    end
  end
end
