module AhoyDashboard
  module Digests
    module Feature
      def periods
        Preferences.read(preference_scope, :digest)
      end

      def period!(value)
        Digests.period!(value)
      end

      def recipients
        Preferences.read(preference_scope, :recipients)
      end

      def from
        Preferences.read(preference_scope, :from)
      end

      def mailer
        (feature.settings[:mailer].presence || default_mailer).to_s.constantize
      end

      def parent_mailer
        (feature.settings[:parent_mailer].presence || "ActionMailer::Base").to_s.constantize
      end

      def enabled?
        feature.enabled? && periods.any? && recipients.any?
      end

      def last_window(period, now: Time.current)
        Digests.last_window(period!(period), now: now)
      end
    end
  end
end
