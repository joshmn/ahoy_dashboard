module AhoyDashboard
  module Alerts
    module Digests
      extend AhoyDashboard::Digests::Feature

      ROW_LIMIT = 20

      Window = AhoyDashboard::Digests::Window

      class << self
        def send_empty?
          Preferences.read(:alerts, :send_empty)
        end

        private

        def feature
          Alerts
        end

        def preference_scope
          :alerts
        end

        def default_mailer
          "AhoyDashboard::AlertMailer"
        end
      end
    end
  end
end
