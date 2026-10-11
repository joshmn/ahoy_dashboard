module AhoyDashboard
  module CompactNumber
    UNITS = [ [ 1_000_000_000, "B" ], [ 1_000_000, "M" ], [ 1_000, "k" ] ].freeze
    DECIMALS_BELOW = 100

    def self.call(value)
      return "0" if value.blank?

      number = value.to_f
      index = UNITS.index { |threshold, _| number.abs.round >= threshold }
      return number.round.to_s if index.nil?

      scaled = number / UNITS[index].first
      if scaled.abs.round >= 1_000 && index.positive?
        index -= 1
        scaled = number / UNITS[index].first
      end

      printed = scaled.abs.round(1) < DECIMALS_BELOW ? format("%.1f", scaled) : scaled.round.to_s

      "#{printed}#{UNITS[index].last}"
    end
  end
end
