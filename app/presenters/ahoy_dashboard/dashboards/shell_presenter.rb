# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class ShellPresenter
      attr_reader :grid_reports, :funnels, :funnel_count

      def initialize(reports:, funnels:, funnel_count:, pinned:)
        @grid_reports = reports
        @funnels = funnels
        @funnel_count = funnel_count
        @pinned = pinned
      end

      def pinned?
        pinned
      end

      def more_funnels?
        funnel_count > funnels.length
      end

      def computed_at
        nil
      end

      private

      attr_reader :pinned
    end
  end
end
