module AhoyDashboard
  module Alerts
    module Rules
      class GoalConversionsFell < Rule
        defines key: "goal_conversions_fell", name: "Goal conversions fell", group: :goals,
                watches: "Every goal", severity: :medium, default_threshold: 30, unit: "percent",
                threshold_range: 1..100,
                phrase: "a goal's conversions over the last 7 days are down %{threshold}%% or more on the 7 days before"

        latches!

        def findings
          readings.goal_days.map do |series|
            drop = percent_drop(series)
            next unless drop && drop >= threshold

            finding(subject: series.name, reading: now.beginning_of_hour.utc.iso8601,
                    headline: "#{series.name} conversions fell #{drop}%",
                    detail: "#{counted(series.this_week, "conversion")} in the last 7 days, " \
                            "against #{number(series.last_week)} the 7 days before.")
          end.select { |value| value }
        end

        def cleared
          readings.goal_days.map do |series|
            drop = percent_drop(series)
            series.name if drop && drop < threshold / 2.0
          end.select { |value| value }
        end

        private

        def percent_drop(series)
          return nil if series.last_week.zero?

          ((series.last_week - series.this_week) * 100.0 / series.last_week).floor
        end
      end
    end
  end
end
