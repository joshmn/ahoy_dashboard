# frozen_string_literal: true

module AhoyDashboard
  module Share
    SMALLEST = 0.1

    class << self
      def fraction(part, of:)
        whole = of.to_f
        return 0.0 unless whole.positive?

        (part.to_f / whole).clamp(0.0, 1.0)
      end

      def label(part, of:)
        whole = of.to_f
        return nil unless whole.positive?

        value = part.to_f / whole * 100

        return "100%" if value >= 99.5
        return "0%" if value.zero?
        return "<#{SMALLEST}%" if value.round(1) < SMALLEST

        value >= 10 ? "#{value.round}%" : "#{value.round(1)}%"
      end
    end
  end
end
