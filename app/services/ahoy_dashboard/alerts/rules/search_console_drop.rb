module AhoyDashboard
  module Alerts
    module Rules
      class SearchConsoleDrop < Rule
        SUBJECT = "Search Console".freeze

        latches!

        def findings
          drop = weekly_drop
          return [] unless drop && drop >= threshold

          [ finding(subject: SUBJECT, reading: weeks.ends_on.iso8601,
                    headline: "#{metric_label.capitalize} fell #{drop}%",
                    detail: "#{counted(current, metric_word)} in the 7 days to #{day(weeks.ends_on)}, " \
                            "against #{number(previous)} the 7 days before.") ]
        end

        def cleared
          return [] unless drop_recovered?(weekly_drop)

          [ SUBJECT ]
        end

        private

        def weeks
          readings.search_console_weeks
        end

        def current
          weeks.current.public_send(metric)
        end

        def previous
          weeks.previous.public_send(metric)
        end

        def weekly_drop
          return nil if weeks.nil?

          percent_drop(previous: previous, current: current)
        end
      end
    end
  end
end
