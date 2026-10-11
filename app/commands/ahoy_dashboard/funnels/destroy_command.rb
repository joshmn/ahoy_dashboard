module AhoyDashboard
  module Funnels
    class DestroyCommand < AhoyDashboard::Command
      def initialize(funnel:)
        @funnel = funnel
      end

      def call
        funnel.destroy!

        broadcast(:ok, funnel)
      end

      private

      attr_reader :funnel
    end
  end
end
