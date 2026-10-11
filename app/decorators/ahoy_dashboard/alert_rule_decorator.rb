module AhoyDashboard
  class AlertRuleDecorator < AhoyDashboard::Decorator
    def watches
      definition&.watches || "nothing this version knows about"
    end
  end
end
