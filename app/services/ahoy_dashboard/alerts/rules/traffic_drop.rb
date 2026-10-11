module AhoyDashboard
  module Alerts
    module Rules
      class TrafficDrop < TrafficRule
        defines key: "traffic_drop", name: "Traffic drop", group: :traffic,
                watches: "Visitors to the whole site", severity: :high,
                default_threshold: 50, unit: "percent", default_floor: 100, threshold_range: 0..99,
                phrase: "visitors over the last 12 full hours are at or below %{threshold}%% of the usual for those hours, " \
                        "and the usual is at least %{floor}"

        private

        def reading
          readings.traffic&.half_day
        end

        def fired?
          reading.usual >= floor && reading.visitors * 100 <= threshold * reading.usual
        end

        def recovered?
          reading.usual >= floor && reading.visitors * 100 > reading.usual * (threshold + (100 - threshold) / 2.0)
        end

        def headline
          "Traffic down #{percent_down}% on the usual"
        end

        def detail
          "#{counted(reading.visitors, "visitor")} in the 12 hours to #{hour(reading.ends_at)}, " \
            "against about #{number(usual)} usual for the same hours over the last #{TrafficQuery::WEEKS} weeks."
        end

        def percent_down
          ((reading.usual - reading.visitors) * 100 / reading.usual).floor
        end
      end
    end
  end
end
