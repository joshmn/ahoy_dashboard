module AhoyDashboard
  module SearchConsole
    SnapshotCounts = Data.define(:rows, :keywords, :totals) do
      def initialize(rows: 0, keywords: 0, totals: 0)
        super
      end
    end
  end
end
