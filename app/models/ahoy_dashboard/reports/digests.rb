module AhoyDashboard
  module Reports
    module Digests
      extend AhoyDashboard::Digests::Feature

      ROW_LIMIT = 5

      Window = AhoyDashboard::Digests::Window

      class << self
        private

        def feature
          Reports
        end

        def preference_scope
          :reports
        end

        def default_mailer
          "AhoyDashboard::ReportMailer"
        end
      end
    end
  end
end
