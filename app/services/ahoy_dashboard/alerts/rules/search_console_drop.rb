module AhoyDashboard
  module Alerts
    module Rules
      class SearchConsoleDrop < Rule
        SUBJECT = "Search Console".freeze

        latches!

        def findings
          return [] unless (drop = percent_drop) && drop >= threshold

          [ finding(subject: SUBJECT, reading: weeks.ends_on.iso8601,
                    headline: "#{metric_label.capitalize} fell #{drop}%",
                    detail: "#{counted(current, metric_word)} in the 7 days to #{day(weeks.ends_on)}, " \
                            "against #{number(previous)} the 7 days before.") ]
        end

        def cleared
          drop = percent_drop
          return [] if drop.nil? || drop >= threshold / 2.0

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

        def percent_drop
          return nil if weeks.nil? || previous.zero?

          ((previous - current) * 100.0 / previous).floor
        end
      end
    end
  end
end
