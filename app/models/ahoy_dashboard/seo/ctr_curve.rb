module AhoyDashboard
  module Seo
    # How often a position gets clicked. Two things read it: the visibility index,
    # which needs a weight per position so that first and eighth are not worth the
    # same, and the opportunity list, which needs the clicks a better position
    # would plausibly have got.
    #
    # These are pooled desktop organic figures, not this site's. That matters and
    # the pages say so: a query somebody types when they already know the answer
    # behaves nothing like one they type to find out, and the pooled curve knows
    # about neither. It is a weighting, not a forecast.
    #
    # Nothing past twenty is given a weight. A result on page three is not a
    # small number of clicks, it is no clicks, and giving it 0.4% invites a
    # visibility score to creep up on movement that changes nothing.
    module CtrCurve
      BY_POSITION = {
        1 => 0.395, 2 => 0.187, 3 => 0.101, 4 => 0.070, 5 => 0.052,
        6 => 0.041, 7 => 0.033, 8 => 0.028, 9 => 0.024, 10 => 0.021,
        11 => 0.019, 12 => 0.017, 13 => 0.015, 14 => 0.014, 15 => 0.013,
        16 => 0.012, 17 => 0.011, 18 => 0.010, 19 => 0.009, 20 => 0.009
      }.freeze

      FLOOR = 0.0

      # What a page-one finish is worth, used as the target the opportunity list
      # measures an upside against. Third rather than first: the top of the page
      # is not available for most searches and pricing every row as if it were
      # produces a list where everything is enormous and nothing is ranked.
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

      def self.depth
        BY_POSITION.keys.max
      end

      # The curve is read at whole positions and Search Console reports an
      # impression-weighted average that lands on 7.4. Rounding down rather than
      # to nearest, because 7.4 means the keyword spent time below seven as well
      # as above it, and rounding up flatters it.
      def self.at_average(position)
        return FLOOR if position.nil? || position.to_f <= 0

        at(position.to_f.floor)
      end
    end
  end
end
