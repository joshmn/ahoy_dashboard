module AhoyDashboard
  module Alerts
    module Digests
      ROW_LIMIT = 20

      PERIODS = AhoyDashboard::Digests::PERIODS
      Window = AhoyDashboard::Digests::Window
      UnknownPeriodError = AhoyDashboard::Digests::UnknownPeriodError

      def self.settings
        Alerts.settings
      end

      def self.periods
        Preferences.read(:alerts, :digest)
      end

      def self.period!(value)
        AhoyDashboard::Digests.period!(value)
      end

      def self.recipients
        Preferences.read(:alerts, :recipients)
      end

      def self.from
        Preferences.read(:alerts, :from)
      end

      def self.send_empty?
        Preferences.read(:alerts, :send_empty)
      end

      def self.mailer
        (settings[:mailer].presence || "AhoyDashboard::AlertMailer").to_s.constantize
      end

      def self.parent_mailer
        (settings[:parent_mailer].presence || "ActionMailer::Base").to_s.constantize
      end

      def self.enabled?
        Alerts.enabled? && periods.any? && recipients.any?
      end

      def self.last_window(period, now: Time.current)
        AhoyDashboard::Digests.last_window(period!(period), now: now)
      end
    end
  end
end
