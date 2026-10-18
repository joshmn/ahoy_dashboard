module AhoyDashboard
  module Alerts
    def self.settings
      AhoyDashboard.config.alerts
    end

    def self.enabled?
      Features.on?(:alerts) && installed?
    end

    def self.installed?
      Installation.installed?(:alerts)
    end

    def self.notifier
      AhoyDashboard.config.alert_notifier
    end

    def self.deliverable?
      notifier.respond_to?(:call)
    end
  end
end
