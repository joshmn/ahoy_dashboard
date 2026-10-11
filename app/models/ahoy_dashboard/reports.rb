module AhoyDashboard
  # The numbers, whether or not anything changed.
  #
  # Alerts send when something crosses a line, which means a quiet month sends
  # nothing and somebody has to remember to go and look. This is the other half:
  # one email a day, week or month with the whole site's traffic in it and the
  # period before it to read the figures against.
  #
  # It covers the whole site the way the dashboard does with nothing switched on:
  # no filter, no segment, crawlers left out.
  module Reports
    def self.settings
      AhoyDashboard.config.reports
    end

    def self.enabled?
      Features.on?(:reports) && installed?
    end

    def self.installed?
      Installation.installed?(:reports)
    end
  end
end
