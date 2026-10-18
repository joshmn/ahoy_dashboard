module AhoyDashboard
  module Seo
    module Periods
      FLOOR_DAYS = 28
      TOO_SHORT = %w[realtime day yesterday].freeze
      EVERYTHING = "all".freeze
      WIDE = "28d".freeze

      class << self
        def all
          AhoyDashboard::Period::ALL.reject { |period| TOO_SHORT.include?(period.key) }
        end

        def wide
          AhoyDashboard::Period.find(WIDE)
        end

        def widen_label
          "Show the #{wide.label.downcase}"
        end

        def widened(query)
          query.with(period: wide.key, from: nil, to: nil).to_query
        end

        def wide_enough?(query)
          return true if query.period.key == EVERYTHING

          range = query.range
          return false if range.nil? || TOO_SHORT.include?(query.period.key)

          (range.end.to_date - range.begin.to_date).to_i + 1 >= FLOOR_DAYS
        end

        def menu(query, custom: true)
          AhoyDashboard::PeriodMenu.items(query: query, periods: all, custom: custom) { |period, _seed| yield(period) }
            .map(&:to_menu_item)
        end
      end
    end
  end
end
