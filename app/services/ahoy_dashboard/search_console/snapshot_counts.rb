# frozen_string_literal: true

module AhoyDashboard

  module SearchConsole

    class SnapshotCounts
      attr_reader :rows, :keywords, :totals

      def initialize(rows: 0, keywords: 0, totals: 0)
        @rows = rows
        @keywords = keywords
        @totals = totals
      end
    end
  end
end
