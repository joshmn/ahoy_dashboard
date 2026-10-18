module AhoyDashboard
  module RangeHint
    WIDER = "Try a wider date range.".freeze
    DROP_FILTER = "drop one of the filters".freeze

    class << self
      def call(filters, drop: DROP_FILTER)
        filters.any? ? "Try a wider date range, or #{drop}." : WIDER
      end
    end
  end
end
