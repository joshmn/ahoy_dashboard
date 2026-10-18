module AhoyDashboard
  module Seo
    module CtrCurve
      BY_POSITION = {
        1 => 0.395, 2 => 0.187, 3 => 0.101, 4 => 0.070, 5 => 0.052,
        6 => 0.041, 7 => 0.033, 8 => 0.028, 9 => 0.024, 10 => 0.021,
        11 => 0.019, 12 => 0.017, 13 => 0.015, 14 => 0.014, 15 => 0.013,
        16 => 0.012, 17 => 0.011, 18 => 0.010, 19 => 0.009, 20 => 0.009
      }.freeze

      FLOOR = 0.0

      REALISTIC_TARGET = 3

      def self.at(position)
        return FLOOR if position.nil?

        BY_POSITION.fetch(position.to_i, FLOOR)
      end

      def self.target
        at(REALISTIC_TARGET)
      end

      def self.best
        BY_POSITION.fetch(1)
      end
    end
  end
end
