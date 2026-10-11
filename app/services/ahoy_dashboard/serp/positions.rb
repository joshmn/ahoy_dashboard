module AhoyDashboard
  module Serp
    module Positions
      def self.absolute(reported:, index:, start:)
        value = reported.to_i
        return value if value > start
        return start + value if value.positive?

        start + index + 1
      end
    end
  end
end
