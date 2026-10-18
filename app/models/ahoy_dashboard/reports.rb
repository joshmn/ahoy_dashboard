module AhoyDashboard
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
