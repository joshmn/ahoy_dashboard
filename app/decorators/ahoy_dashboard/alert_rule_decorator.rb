module AhoyDashboard
  class AlertRuleDecorator < AhoyDashboard::Decorator
    include AhoyDashboard::SeverityBadge

    STATUS_OPTIONS = [ [ "On", true ], [ "Off", false ] ].freeze

    def watches
      definition&.watches || "nothing this version knows about"
    end

    def status_options
      STATUS_OPTIONS
    end

    def severity_options
      AlertRule.severities.keys.map { |key| [ key.capitalize, key ] }
    end
  end
end
