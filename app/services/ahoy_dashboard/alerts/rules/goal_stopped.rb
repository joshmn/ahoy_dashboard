module AhoyDashboard
  module Alerts
    module Rules
      class GoalStopped < Rule
        defines key: "goal_stopped", name: "Goal stopped converting", group: :goals,
                watches: "Every goal", severity: :high,
                phrase: "a goal that converted on each of the 7 days before has none in the last 24 hours"

        latches!

        def findings
          readings.goal_days.select { |series| stopped?(series) }.map do |series|
            finding(subject: series.name, reading: this_hour,
                    headline: "#{series.name} stopped converting",
                    detail: "No conversions in the last 24 hours, after " \
                            "#{counted(series.week_before_last_day.sum, "conversion")} in the 7 days before.")
          end
        end

        def cleared
          readings.goal_days.select { |series| series.last_day.positive? }.map(&:name)
        end

        private

        def stopped?(series)
          series.last_day.zero? && series.week_before_last_day.all?(&:positive?)
        end
      end
    end
  end
end
