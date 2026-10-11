module AhoyDashboard
  module Alerts
    module Rules
      class SpendNearCap < Rule
        defines key: "spend_near_cap", name: "Nearing the monthly cap", group: :spend,
                watches: "The search provider's monthly cap", severity: :medium,
                default_threshold: Serp::NEAR_CAP_PERCENT, unit: "percent", threshold_range: 1..99,
                phrase: "the month's search units reach %{threshold}%% of the provider's monthly cap"

        # Once a month, and again if the cap is raised and the new one is passed
        # too. The cap is in the reading for that second case: raising it is a
        # decision to spend more, and going through 80% of the bigger number is
        # news again.
        def findings
          spend = readings.serp_spend
          return [] if spend.nil? || !spend.near?(threshold)

          [ finding(subject: spend.name, reading: reading(spend), headline: headline(spend),
                    detail: detail(spend)) ]
        end

        private

        def reading(spend)
          "#{spend.starts_on.iso8601}:#{spend.cap}"
        end

        def headline(spend)
          "#{Settings::Display.serp_label(spend.name)} is #{spend.percent}% through this month's cap"
        end

        def detail(spend)
          parts = [ "#{counted(spend.used, "unit")} of #{number(spend.cap)} since #{day(spend.starts_on)}, " \
                    "#{number(spend.left)} left." ]

          parts << if spend.over?
            "The checks already scheduled would spend another #{number(spend.forecast.total)} " \
              "before #{day(spend.forecast.through.to_date)}, so the cap stops them at #{number(spend.cap)}."
          elsif spend.forecast.any?
            "The checks already scheduled spend another #{number(spend.forecast.total)} " \
              "before #{day(spend.forecast.through.to_date)}."
          else
            "Nothing is scheduled for the rest of the month."
          end

          parts.join(" ")
        end
      end
    end
  end
end
