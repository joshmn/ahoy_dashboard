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
            drop = drop_for(series)
            next unless drop && drop >= threshold

            finding(subject: series.name, reading: this_hour,
                    headline: "#{series.name} conversions fell #{drop}%",
                    detail: "#{counted(series.this_week, "conversion")} in the last 7 days, " \
                            "against #{number(series.last_week)} the 7 days before.")
          end.compact
        end

        def cleared
          readings.goal_days.select { |series| drop_recovered?(drop_for(series)) }.map(&:name)
        end

        private

        def drop_for(series)
          percent_drop(previous: series.last_week, current: series.this_week)
        end
      end
    end
  end
end
