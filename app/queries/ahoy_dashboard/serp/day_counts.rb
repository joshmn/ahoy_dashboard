module AhoyDashboard
  module Serp
    DayCounts = Data.define(:date, :counts) do
      def count(key)
        counts.fetch(key.to_s, 0)
      end

      def total
        counts.values.sum
      end
    end
  end
end
