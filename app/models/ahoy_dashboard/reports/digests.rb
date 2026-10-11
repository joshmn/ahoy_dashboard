module AhoyDashboard
  module Reports
    module Digests
      ROW_LIMIT = 5

      PERIODS = AhoyDashboard::Digests::PERIODS
      Window = AhoyDashboard::Digests::Window
      UnknownPeriodError = AhoyDashboard::Digests::UnknownPeriodError

      def self.settings
        Reports.settings
      end

      def self.periods
        Preferences.read(:reports, :digest)
      end

      def self.period!(value)
        AhoyDashboard::Digests.period!(value)
      end

      def self.recipients
        Preferences.read(:reports, :recipients)
      end

      def self.from
        Preferences.read(:reports, :from)
      end

      def self.mailer
        (settings[:mailer].presence || "AhoyDashboard::ReportMailer").to_s.constantize
      end

      def self.parent_mailer
        (settings[:parent_mailer].presence || "ActionMailer::Base").to_s.constantize
      end

      def self.enabled?
        Reports.enabled? && periods.any? && recipients.any?
      end

      def self.last_window(period, now: Time.current)
        AhoyDashboard::Digests.last_window(period!(period), now: now)
      end
    end
  end
end
