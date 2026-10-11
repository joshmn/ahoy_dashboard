module AhoyDashboard
  module Alerts
    module Rules
      class TrafficRule < Rule
        SUBJECT = "Traffic".freeze

        latches!

        def findings
          return [] if reading.nil? || !fired?

          [ finding(subject: SUBJECT, reading: local(reading.ends_at).to_date.iso8601,
                    headline: headline, detail: detail) ]
        end

        def cleared
          return [] if reading.nil? || !recovered?

          [ SUBJECT ]
        end

        private

        def usual
          reading.usual.round
        end

        def hour(time)
          local(time).strftime("%-l %p")
        end

        def weekday(time)
          local(time).strftime("%A")
        end
      end
    end
  end
end
