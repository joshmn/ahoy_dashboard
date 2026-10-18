module AhoyDashboard
  module PeriodMenu
    class << self
      def items(query:, periods: AhoyDashboard::Period::ALL, custom: true)
        offered = custom ? periods : periods.reject(&:custom?)

        offered.map do |period|
          AhoyDashboard::MenuOption.new(
            label: period.label,
            value: period.key,
            path: yield(period, seed(query, period)),
            active: period.key == query.period.key
          )
        end
      end

      private

      def seed(query, period)
        return {} unless period.custom?

        { from: query.range_from_field, to: query.range_to_field }
      end
    end
  end
end
