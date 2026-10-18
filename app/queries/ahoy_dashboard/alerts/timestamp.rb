module AhoyDashboard
  module Alerts
    module Timestamp
      class << self
        def literal(time)
          "#{Sql.literal(time.utc.strftime("%Y-%m-%d %H:%M:%S.%6N"))}::timestamp"
        end
      end
    end
  end
end
