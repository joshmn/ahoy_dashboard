# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    ShellPresenter = Data.define(:reports, :funnels, :funnel_count, :pinned) do
      def grid_reports
        reports
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
    end
  end
end
