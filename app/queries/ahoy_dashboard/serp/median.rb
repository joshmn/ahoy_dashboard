module AhoyDashboard
  module Serp
    module Median
      class << self
        def of(positions)
          sorted = positions.select { |value| value }.sort
          return nil if sorted.empty?

          middle = sorted.size / 2
          return sorted[middle] if sorted.size.odd?

          ((sorted[middle - 1] + sorted[middle]) / 2.0).round(1)
        end
      end
    end
  end
end
