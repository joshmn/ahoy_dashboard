module AhoyDashboard
  # Being told, rather than finding out on a Monday.
  #
  # A position that fell on a Thursday is a week old by the time anybody opens
  # the rankings page, and everything a rule fires on is already written every
  # time a check runs.
  #
  # This is the first thing in the dashboard that leaves the box, and it only
  # does so if the host says how. An event is always written to the feed.
  # config.alert_notifier is called with each one as it fires, if one is set, and
  # the alert emails under Settings, Emails send one a day, week or month with
  # all of them.
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
