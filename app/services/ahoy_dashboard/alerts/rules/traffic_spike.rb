module AhoyDashboard
  module Alerts
    module Rules
      class TrafficSpike < TrafficRule
        defines key: "traffic_spike", name: "Traffic spike", group: :traffic,
                watches: "Visitors to the whole site", severity: :medium,
                default_threshold: 3, unit: "times the usual", default_floor: 20, threshold_range: 2..Float::INFINITY,
                phrase: "visitors in the last full hour reach %{threshold} times the usual for that hour and weekday, " \
                        "and at least %{floor}"

        private

        def reading
          readings.traffic&.hour
        end

        def fired?
          reading.visitors >= floor && reading.visitors >= threshold * reading.usual
        end

        def recovered?
          reading.visitors < floor || reading.visitors < reading.usual * (1 + (threshold - 1) / 2.0)
        end

        def headline
          "Traffic spike: #{counted(reading.visitors, "visitor")} in an hour"
        end

        def detail
          window = "#{hour(reading.starts_at)} to #{hour(reading.ends_at)}"
          return "#{window}, when a #{weekday(reading.starts_at)} usually brings nobody." if usual.zero?

          "#{window}, when a #{weekday(reading.starts_at)} usually brings about #{number(usual)}. " \
            "That's #{multiple} times the usual."
        end

        def multiple
          times = (reading.visitors / reading.usual).round(1)
          number(times == times.to_i ? times.to_i : times)
        end
      end
    end
  end
end
